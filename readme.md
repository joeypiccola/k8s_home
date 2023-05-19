# kubernetes @ home

## Talos and Kubernetes Versions

Talos and Kubernetes versions are a bit interdependent. You can find a support-matrix [here](https://www.talos.dev/v1.4/introduction/support-matrix/). Talos releases are [here](https://github.com/siderolabs/talos/releases).

## Rebuild from scratch

### Build the infrastructure with Terraform

```bash
# from repo root
cd terraform
terraform apply
```

### Bootstrap the systems with Talos

For this you can use any controlplane IP from `talos/talenv.yaml`.

```bash
# from repo root
cd talos/clusterconfig
talosctl bootstrap --nodes 10.0.3.151
```

### Create and apply talos-vmtoolsd-config secret

This secret is used by the `talos-vmtoolsd` daemonset. Without it, these pods will be stuck in `ContainerCreating`.

```bash
# from repo root
cd talos/clusterconfig
talosctl -n 10.0.3.151 config new vmtoolsd-secret.yaml --roles os:admin
kubectl -n kube-system create secret generic talos-vmtoolsd-config --from-file=talosconfig=./vmtoolsd-secret.yaml
rm ./vmtoolsd-secret.yaml
```

### Install GitOps Toolkit (GOTK) components

**Imperatively** install [flux](https://fluxcd.io/flux/components/) at the version specified in `kubernetes/flux-bootstrap/flux-repo.yaml`. `flux` and `yq` binaries are required here. At the time of this writing the `flux` binary version `0.41.2` is being used.

```bash
# from repo root
yq '.spec.ref.tag' kubernetes/flux/repositories/git/flux.yaml | xargs -I{} flux install --components-extra=image-reflector-controller,image-automation-controller --version={} --export | kubectl apply -f -
```

### Create aɡe secret for SOPS

Once installed, create your `sops-age` secret.

```bash
cat 'wherever you keep this file/keys.txt' | kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/dev/stdin
```

### Apply kustomizations

```bash
# from repo root
k apply --kustomize kubernetes/flux
k apply --kustomize kubernetes/infrastructure
```

### Helm Charts

The following are a few commands for working with Helm charts and their releases.

`helm repo list` to list chart repositories.

`helm repo update` to update information of available charts locally from chart repositories.

`helm repo add metallb https://metallb.github.io/metallb` for adding the `metallb` repo locally.

`helm search repo metallb --versions` to list chart versions / releases.
