# kubernetes @ home

## Talos and Kubernetes Versions

Talos and Kubernetes versions are a bit interdependent. You can find a support-matrix [here](https://www.talos.dev/v1.4/introduction/support-matrix/). Talos releases are [here](https://github.com/siderolabs/talos/releases).

## Talos and Talhelper

Use `talhelper` to gen talos configs. It's a wrapper around `talosctl config new` that adds some niceties. The following will generate individual talos node config files in `k8s_home/talos/clusterconfig`. Regenerating configs is only necessary if you want to change the talos version or the talos config.

```bash
# from repo root
cd talos
talhelper genconfig
```

## Rebuild from scratch

### Build the infrastructure with Terraform

```bash
# from repo root
cd terraform
t apply
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

### Patch control plane machines with admission control

For this to work `control-1.piccola.us` names must be in DNS. "That is what allows you to run privileges in all namespaces", move away from this using a kyverno policy.

```bash
# from repo root
cd talos/clusterconfig
talosctl patch machineconfig -n control-1.piccola.us,control-2.piccola.us,control-3.piccola.us,control-4.piccola.us,control-5.piccola.us --patch-file ../patches/admissionControl-patch.yaml
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
