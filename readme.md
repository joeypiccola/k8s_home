# kubernetes @ home

## Rebuild from scratch

### Build the infrastructure with Terraform

```bash
cd terraform
terraform apply
```

### Bootstrap the systems with Talos

For this you can use any controlplane IP from `talos/talenv.yaml`.

```bash
cd talos/clusterconfig
talosctl bootstrap --nodes 10.0.3.151
```

### Create and apply talos-vmtoolsd-config secret

This secret is used by the `talos-vmtoolsd` daemonset. Without it, these pods will be stuck in `ContainerCreating`.

```bash
cd talos/clusterconfig
talosctl -n 10.0.3.151 config new vmtoolsd-secret.yaml --roles os:admin
kubectl -n kube-system create secret generic talos-vmtoolsd-config --from-file=talosconfig=./vmtoolsd-secret.yaml
rm ./vmtoolsd-secret.yaml
```

### install GOTK

**Imperatively** install flux at the version specified in `kubernetes/flux-bootstrap/flux-repo.yaml`. The `flux` and `yq` binaries are required here. At the time of this writing the flux binary version `0.38.3` is being used.

```bash
# cd to root of k8s_home repo
yq '.spec.ref.tag' kubernetes/flux/repositories/git/flux.yaml | xargs -I{} flux install --components-extra=image-reflector-controller,image-automation-controller --version={} --export | kubectl apply -f -
```

Once installed, create your sops secret.

```bash
cat 'wherever you keep this file/keys.txt' | kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/dev/stdin
```

Kickstart flux kustomizations. This will

`k apply --kustomize kubernetes/flux`
`k apply --kustomize kubernetes/infrastructure`

#### old notes

once cluster is up run the following to bootstrap flux

```bash
# cd to root of repo
flux bootstrap github --owner=$GITHUB_USER --repository=k8s_home --branch=main --path=clusters/production --personal=true --reconcile=true
```
