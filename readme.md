# kubernetes @ home

Run Kubernetes using Talos Linux in VMware.

## Talos

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
brew tap siderolabs/talos
brew install talosctl
brew install talhelper
```

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

#### Talos Config Node Patches

Talos support patching node configs during config generation. This is done one of two ways, 1) in the `talosconfig.yaml` file via yaml patching or 2) via a patch file applied to the nodes after provisioning.

##### VMware Tools

VMware tools, more specifically [talos-vmtoolsd](https://github.com/mologie/talos-vmtoolsd), is configured via a yaml patch during talos node config generation. For this to work correctly we also must create the secret `talos-vmtoolsd-config` which we do later. This secret contains a full `talosconfig` file that we generate later with the appropriate roles so the containers running vm tools can run with the correct privileges.

## SOPS and age

All secrets in this repo are encrypted with [SOPS](https://github.com/getsops/sops) leveraging [age](https://github.com/FiloSottile/age). `age-keygen -o myKey.txt` was used to generate the public key and age secret. SOPS is configured to use the age public key via the `.sops.yaml` in the root of this repo. Via the VSCode extension `signageos.signageos-vscode-sops` we can automatically encrypt/decrypt secrets in place. In order for this to work you must have `SOPS_AGE_KEY` set as an environment variable (this is a requirement of SOPS). `SOPS_AGE_KEY` is set by the git ignored `.envrc` file in the root of this repo.

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

### Create and apply talos-vmtoolsd-config secret

This secret is used by the `talos-vmtoolsd` daemonset (that we patched in during talos node config generation). Without it, these pods will be stuck in `ContainerCreating`. Again, this is full `talosconfig` that is written to the secret.

```shell
# from repo root
cd talos/clusterconfig
talosctl -n 10.0.3.151 config new talosconfig_vmtoolsd.yaml --roles os:admin
kubectl -n kube-system create secret generic talos-vmtoolsd-config --from-file=talosconfig=./talosconfig_vmtoolsd.yaml
rm ./talosconfig_vmtoolsd.yaml
```

### Patch control plane machines with admission control

For this to work `control-1.piccola.us` names must be in DNS. "That is what allows you to run privileges in all namespaces", move away from this using a kyverno policy.

```shell
# from repo root
cd talos/clusterconfig
talosctl patch machineconfig -n control-1.piccola.us,control-2.piccola.us,control-3.piccola.us,control-4.piccola.us,control-5.piccola.us --patch-file ../patches/admissionControl-patch.yaml
```

### Bootstrap the cluster (flux)

**Imperatively** install [flux](https://github.com/fluxcd/flux2) at the version specified in `kubernetes/flux/repositories/git/flux.yaml`. `flux` and `yq` binaries are required here. At the time of this writing the `flux` binary version `2.1.2` is being used.

```shell
# from repo root
yq '.spec.ref.tag' kubernetes/flux/repositories/git/flux.yaml | xargs -I{} flux install --components-extra=image-reflector-controller,image-automation-controller --version={} --export | kubectl apply -f -
```

### Create age secret for SOPS decryption on the cluster

Once installed, create your `sops-age` secret. This is using the `SOPS_AGE_KEY` environment variable set in the `.envrc` file in the root of this repo.

```shell
# from repo root
echo "$SOPS_AGE_KEY" | kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/dev/stdin
```

### How cluster secret decryption with flux works

When we bootstrapped the cluster with flux we created the secret `cluster-secrets` in the `flux-system` namespace. This secret contains key/value's that are substituted in to manifest files.

Q: How does this substitution work?
A:

### Apply kustomizations

```shell
# from repo root
k apply --kustomize kubernetes/flux
k apply --kustomize kubernetes/infrastructure
k apply --kustomize kubernetes/applications
```

## Troubleshooting

### rook-ceph

`kubectl --namespace rook-ceph get cephcluster` to get the status of the cluster.

### helm charts

The following are a few commands for working with Helm charts and their releases.

`helm repo list` to list chart repositories.

`helm repo update` to update information of available charts locally from chart repositories.

`helm repo add metallb https://metallb.github.io/metallb` for adding the `metallb` repo locally.

`helm search repo metallb --versions` to list chart versions / releases.

`helm list --all-namespaces --all` to list installed charts.

`k delete hr -n pihole pihole` to delete a HelmRelease named pihole in the pihole namespace.

### kustomizations with flux

`k get kustomizations.kustomize.toolkit.fluxcd.io -n flux-system` to list kustomization in `flux-system` namespace

`flux reconcile kustomization flux-install` to reconcile the `flux-install` kustomization
