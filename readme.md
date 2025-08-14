# kubernetes @ home

Run Kubernetes using Talos Linux on bare metal.

Tools you'll need.

- kubectl
- talhelper
- talosctl
- 1password
- taskfile
- helm

## What is Talos

Talos Linux is Linux designed for Kubernetes - secure, immutable, and minimal.

### Talos and Kubernetes Versions

Talos and Kubernetes versions are a bit interdependent. You can find a support-matrix [here (example v1.5, update URL as needed)](https://www.talos.dev/v1.5/introduction/support-matrix/). Talos releases are [here](https://github.com/siderolabs/talos/releases). Use the release page to get the latest patch. Kubernetes releases are [here](https://kubernetes.io/releases/). These versions are used in the `talos/talenv.yaml` file.

### Talos Configs

We're going to use `talhelper` to generate talos node configs. Talos node configs are node specific and are applied to the nodes later via a task. Normally we'd do something like `talosctl gen config myCluster https://<VIP>:<port>` to generate talos node configs but this doesn't scale very well. With `talhelper` we can leverage `talos/talconfig.yaml` + `talos/talenv.yaml` + `talos/talsecret.sops.yaml` to generate all talos node configs at once. The following is a brief description of each file.

- `talos/talconfig.yaml`: talos config template (created by hand initially via a [starter template](https://github.com/budimanjojo/talhelper/blob/master/example/talconfig.yaml)) This is a `talhelper` specific config that leverages variable substitution from `talos/talenv.yaml` (e.g. `${domainName}`).
- `talos/talenv.yaml`: talos environment variables that are injected into talos node config files.
- `talos/talsecret.sops.yaml`: talos secrets that are injected into talos node config files. It holds k8s certs/keys, talos specific certs/keys and bootstrap tokens that get injected into talos config files. This file was created with `talhelper gensecret > talsecret.sops.yaml`, only needed once! This file was encrypted with `sops -e -i talos/talsecret.sops.yaml` discussed later.

#### Generate Talos Configs

Use `talhelper` to generate talos configs. The following will generate individual talos node config files and a `talosconfig` in `talos/clusterconfig`. Regenerating configs is only necessary if you want to change the talos version, kubernetes version, or a talos config setting.

`task talos:genconfig`

#### SOPS and talhelper

`talsecret.sops.yaml` is encrypted with [SOPS](https://github.com/getsops/sops) leveraging [age](https://github.com/FiloSottile/age). `age-keygen -o myKey.txt` was used to generate the public key and age secret. SOPS is configured to use the age public key via the `.sops.yaml` in the root of this repo to encrypt files. Via the VSCode extension `signageos.signageos-vscode-sops` we can automatically encrypt/decrypt secrets in place. In order for this to work you must have `SOPS_AGE_KEY` set as an environment variable (this is a requirement of SOPS). `SOPS_AGE_KEY` is set by the git ignored `.envrc` file in the root of this repo.

The `.sops.yaml` file defines rules for what files via path filtering are in scope for encryption in addition to what keys in those files should be encrypted. To onboard a file for encryption (not the entire file, just the keys that match the rules) you can run `sops -e -i ./testing/test.sops.yaml`.

## Rebuild from scratch

### scenario 1

nodes are responsive to `talosctl` and you're knowingly doing a from scratch rebuild.

1. reset the nodes

`> task talos:reset-nodes`

1. pxe boot the nodes (not covered here)

1. regenerate configs if needed (likely need to update `talhelper` and `talosctl`)

`> task talos:genconfig`

1. apply the configs.

`> talos:apply-config`

1. initiate bootstrap.

`> task talos:bootstrap`

1. get kubeconfig if needed, only required if new talos secrets were generated.

`> task talos:get-kubeconfig`

1. begin to install core infra. cilium and argocd will be managed under argocd later.

```plaintext
> task install:gateway_api_crds
> task install:cilium
> task install:argocd
> task stage:onepassword_secrets
```

1. install argo app of apps `infra`.

`> k apply -n argocd -f argocd/aoa_infra.yaml`

1. now that longhorn is installed, proceed to the longhorn UI to restore volumes (port forward). delete any orphaned data on longhorn mounted disk (Settings\Orphaned Data)

- restore volumes one at a time, checking "Use Previous Name"
- restore volume PV/PVC, go to Create PV/PVC and ensure `Create PVC` and `Use Previous PVC` are checked

1. install argo app of apps `apps`.

`> k apply -n argocd -f argocd/aoa_apps.yaml`
