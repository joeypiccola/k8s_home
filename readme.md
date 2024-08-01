# kubernetes @ home

Run Kubernetes using Talos Linux in VMware.

## What is Talos

Talos Linux is Linux designed for Kubernetes - secure, immutable, and minimal.

### Talos and Kubernetes Versions

Talos and Kubernetes versions are a bit interdependent. You can find a support-matrix [here (example v1.5, update URL as needed)](https://www.talos.dev/v1.5/introduction/support-matrix/). Talos releases are [here](https://github.com/siderolabs/talos/releases). Use the release page to get the latest patch. Kubernetes releases are [here](https://kubernetes.io/releases/). These versions are used in the `talos/talenv.yaml` file.

#### Talos Configs

We're going to use `talhelper` to generate talos node configs. Talos node configs are node specific and are used later during infrastructure provisioning. Normally we'd do something like `talosctl gen config myCluster https://<VIP>:<port>` to generate talos node configs but this doesn't scale very well. With `talhelper` we can leverage `talos/talconfig.yaml` + `talos/talenv.yaml` + `talos/talsecret.sops.yaml` to generate all talos node configs at once. The following is a brief description of each file.

- `talos/talconfig.yaml`: talos config template (created by hand initially via a [starter template](https://github.com/budimanjojo/talhelper/blob/master/example/talconfig.yaml)) This is a `talhelper` specific config that leverages variable substitution from `talos/talenv.yaml` (e.g. `${domainName}`).
- `talos/talenv.yaml`: talos environment variables that are injected into talos node config files.
- `talos/talsecret.sops.yaml`: talos secrets that are injected into talos node config files. It holds k8s certs/keys, talos specific certs/keys and bootstrap tokens that get injected into talos config files. This file was created with `talhelper gensecret > talsecret.sops.yaml`, only needed once! This file was encrypted with `sops -e -i talos/talsecret.sops.yaml` discussed later.

#### Installs

```shell
brew install siderolabs/tap/talosctl # if not found -> "brew link --overwrite talosctl"
brew install talhelper
```

At the time of this writing: July 18th 2024:

```plaintext
➜ talosctl version
Client:
Tag:         v1.7.5
➜ talhelper --version
talhelper version 3.0.4
```

#### Talos Config Node Patches

Talos supports patching node configs during config generation. This is done one of two ways, 1) in the `talconfig.yaml` file via yaml patching or 2) via a patch file applied to the nodes after provisioning.

##### VMware Tools

VMware tools, more specifically [talos-vmtoolsd](https://github.com/mologie/talos-vmtoolsd), is configured via a yaml patch during talos node config generation (see `talconfig.yaml`). For this to work correctly we also must create the k8s secret `talos-vmtoolsd-config` which we do later. This secret contains a full `talosconfig` file that we also generate later with the appropriate role so the containers running vm tools can run with the correct privileges. More specifically, the `talosconfig` is used with `talosapi.NewLocalClient` to connect to the talos node API to get info that can be reported back to VMware.

#### Generate Talos Configs

Use `talhelper` to generate talos configs. The following will generate individual talos node config files and a `talosconfig` in `talos/clusterconfig`. Regenerating configs is only necessary if you want to change the talos version, kubernetes version, or a talos config setting.

```shell
# from repo root
cd talos
talhelper genconfig
tree talos/clusterconfig
talos/clusterconfig
├── talos-control-1.piccola.us.yaml
├── talos-control-2.piccola.us.yaml
├── talos-control-3.piccola.us.yaml
├── talos-control-4.piccola.us.yaml
├── talos-control-5.piccola.us.yaml
└── talosconfig
```

## SOPS and age

All secrets in this repo are encrypted with [SOPS](https://github.com/getsops/sops) leveraging [age](https://github.com/FiloSottile/age). `age-keygen -o myKey.txt` was used to generate the public key and age secret. SOPS is configured to use the age public key via the `.sops.yaml` in the root of this repo to encrypt files. Via the VSCode extension `signageos.signageos-vscode-sops` we can automatically encrypt/decrypt secrets in place. In order for this to work you must have `SOPS_AGE_KEY` set as an environment variable (this is a requirement of SOPS). `SOPS_AGE_KEY` is set by the git ignored `.envrc` file in the root of this repo.

The `.sops.yaml` file defines rules for what files via path filtering are in scope for encryption in addition to what keys in those files should be encrypted. To onboard a file for encryption (not the entire file, just the keys that match the rules) you can run `sops -e -i ./testing/test.sops.yaml`.

## Rebuild from scratch

### Build the infrastructure with Terraform

Leverages git ignored `.envrc` to set environment variables for vCenter authentication.

```shell
# terraform/.envrc
export VSPHERE_USER=''
export VSPHERE_PASSWORD=''
export VSPHERE_SERVER=''
export VSPHERE_ALLOW_UNVERIFIED_SSL='true'
```

Terraform will create VMs leveraging Talos' VMware OVA specific image. The Talos version is dynamically parsed from `talenv.yaml`. Each VM built is passed its specific Talos config via VMware's `guestinfo` mechanism. At boot, Talos knows to grab the config from `guestinfo.talos.config`.

```shell
# from repo root
cd terraform
t apply
```

### Bootstrap the cluster (talos)

Leverages git ignored `.envrc` to set environment variables for `talosctl` authentication.

```shell
# talos/clusterconfig/.envrc
export TALOSCONFIG=./talosconfig
```

For this you can use any controlplane IP from `talos/talenv.yaml`.

```shell
# from repo root
cd talos/clusterconfig
talosctl bootstrap --nodes 10.0.3.151
```

At this point, Talos will form an etcd cluster, and start the Kubernetes control plane components. This will take a few minutes. Once complete, if this is a new cluster with new generated secrets via `talhelper gensecret` you can run the following to download your Kubernetes client configuration and get started. Running this command will add (merge) you new cluster into your local Kubernetes configuration.

`talosctl kubeconfig --nodes 10.0.3.151 --endpoints 10.0.3.151`

#### Create and apply talos-vmtoolsd-config secret

This secret is used by the `talos-vmtoolsd` daemonset (that we patched in during talos node config generation). Without it, these pods will be stuck in `ContainerCreating`. Again, this is full `talosconfig` that is written to the secret. More info on this back in [VMware Tools](#vmware-tools).

todo(joey): this is not great. sharing same talosconfig we use to admin the cluster with the vmtoolsd daemonset.

```shell
# from repo root
cd talos/clusterconfig
talosctl -n 10.0.3.151 config new talosconfig_vmtoolsd.yaml --roles os:admin
kubectl -n kube-system create secret generic talos-vmtoolsd-config --from-file=talosconfig=./talosconfig_vmtoolsd.yaml
rm ./talosconfig_vmtoolsd.yaml
```

#### Patch control plane machines with admission control

For this to work `control-1.piccola.us` names must be in DNS. "That is what allows you to run privileges in all namespaces", move away from this using a kyverno policy.

```shell
# from repo root
cd talos/clusterconfig
talosctl patch machineconfig -n control-1.piccola.us,control-2.piccola.us,control-3.piccola.us,control-4.piccola.us,control-5.piccola.us --patch-file ../patches/admissionControl-patch.yaml
```

#### talosctl commands

Running from somewhere with a valid TALOSCONFIG env var.

```plaintext
talosctl dashboard
talosctl memory
```

## ArgoCD Notes

Once the cluster is up create argo namespace.

```plaintext
kubectl create namespace argocd
kubectl config set-context --current --namespace=argocd
```

Use helm to imperatively install argo.

```plaintext
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm template argocd argo/argo-cd -n argocd --version 7.3.3 | kubectl apply -f -
```

The following is optional if you want to view the argo dashboard before ingress setup.

```plaintext
# get the argo password
argocd admin initial-password -n argocd
# create a port forward to `argocd-server` pod
# login
argocd login localhost:8080 --username admin
# update the password
argocd account update-password
```

Kick off the app of apps

```plaintext
# from the repo root
k apply -n argocd -f argocd/app-of-apps.yaml
```
