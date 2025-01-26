### Flux

#### Bootstrap the cluster

**Imperatively** install [flux](https://github.com/fluxcd/flux2) at the version specified in `kubernetes/flux/repositories/git/flux.yaml`. `flux` and `yq` binaries are required here. At the time of this writing the `flux` binary version `2.1.2` is being used.

```shell
# from repo root
yq '.spec.ref.tag' kubernetes/flux/repositories/git/flux.yaml | xargs -I{} flux install --components-extra=image-reflector-controller,image-automation-controller --version={} --export | kubectl apply -f -
```

#### Create age secret for SOPS decryption on the cluster

Once installed, create your `sops-age` secret. This is using the `SOPS_AGE_KEY` environment variable set in the `.envrc` file in the root of this repo.

```shell
# from repo root
echo "$SOPS_AGE_KEY" | kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/dev/stdin
```

#### How cluster secret decryption and substitution works with Flux

Yikes, big topic :grimacing:.

##### Decryption

The `sops-age` secret we created earlier is referenced in various kustomize kustomizations via `.spec.decryption`. This `.spec.decryption` element specifies the encryption provider to use and the name of the secret to fetch (gettign the value) to use to decrypt files. This is a flux specific process that `.spec.decryption` is providing.

At the time of the writing, only a few secrets are encrypted that require the age secret to decrypt. If a secret can simply be substituted into a manifest and is not required to exist in a namespace, then they can go in `kubernetes/flux/vars/cluster-secrets.sops.yaml`. An example of a full `.spec.decryption` is below.

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: secrets
  namespace: flux-system
spec:
  # ...omitted for brevity
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

##### Substitution

When we bootstrapped the cluster with flux we created the secret `cluster-secrets` in the `flux-system` namespace. This secret contains key/value's that are substituted in to manifest files.

So how does this work? You have a kustomize kustomization that includes flux kustomization(s) (e.g. resources). The flux kustomization(s) leverage `.spec.patches` to patch "target" downstream flux kustomization's with the `.spec.postBuild` element. The `.spec.postBuild` element leverages `.spec.postBuild.substituteFrom` to do post build variable substitution. In the `.spec.postBuild.substituteFrom` element is a list of places to look for matching keys to perform substitution with the values into manifest. In this case, we're pulling from a `Secret` named `cluster-secrets`. An example of the full patch block is below. Note: in order for this to work properly, the secret `cluster-secrets` must use the `.spec.stringData` field.

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure-networking
  namespace: flux-system
spec:
  # ...omitted for brevity
  patches:
    - patch: |-
        apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: Kustomization
        metadata:
          name: not-used
        spec:
          postBuild:
            substituteFrom:
              - kind: Secret
                name: cluster-secrets
```

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

## Backup and Restore

Backups are facilitated via [VolSync Restic-based backups](https://volsync.readthedocs.io/en/stable/usage/restic/index.html).

Take a snapshot of `sabnzbd` in the media namespace.

`task volsync:snapshot rsrc=sabnzbd namespace=media`

List `sabnzbd` snapshots.

```
task volsync:list rsrc=sabnzbd namespace=media
ID        Time                 Host        Tags        Paths
------------------------------------------------------------
f2ad7280  2023-12-21 05:05:51  volsync                 /data
3815361b  2023-12-22 17:03:59  volsync                 /data
------------------------------------------------------------
2 snapshots
```

Restore `sabnzbd` from the `f2ad7280` snapshot. This is achieved by setting `restoreAsOf` in `./.taskfiles/volsync/ReplicationDestination.tmpl.yaml` to a date after `2023-12-21 05:05:51` but before `2023-12-22 17:03:59` e.g. `2023-12-22T00:00:00-00:00`.

`task volsync:restore rsrc=sabnzbd namespace=media`

List s3 repo contents

```bash
➜ mc ls myminio
[2023-12-20 10:24:20 MST]     0B volsync/
```

List sabnzbd contents in volsync bucket (trailing `/` does this)

```bash
➜ mc ls myminio/volsync/sabnzbd/
[2023-12-20 22:05:50 MST]   155B STANDARD config
[2023-12-21 09:59:48 MST]     0B data/
[2023-12-21 09:59:48 MST]     0B index/
[2023-12-21 09:59:48 MST]     0B keys/
[2023-12-21 09:59:48 MST]     0B snapshots/
```

Copy sabnzbd restic backups to local `./backups/sabnzbd`

```bash
mc cp --recursive myminio/volsync/sabnzbd/ ./backups/sabnzbd
```

List restic snapshots

```bash
➜ restic -r ./backups/sabnzbd snapshots
repository 5e2a3446 opened (version 2, compression level auto)
ID        Time                 Host        Tags        Paths
------------------------------------------------------------
f2ad7280  2023-12-20 22:05:51  volsync                 /data
------------------------------------------------------------
1 snapshots
```

Restore the latest sabnzbd restic snapshot to `./backups/sabnzbd_restore`

```bash
restic -r ./backups/sabnzbd restore latest --target ./backups/sabnzbd_restore
```

List the contents of the restore

```bash
➜ ls -lah ./backups/sabnzbd_restore
total 48
drwxr-xr-x  9 jpiccola  staff   288B Dec 21 08:51 .
drwxr-xr-x  4 jpiccola  staff   128B Dec 21 08:47 ..
drwxrwsr-x  4 jpiccola  staff   128B Dec 18 15:40 Downloads
drwxrwsr-x  8 jpiccola  staff   256B Dec 19 21:31 admin
drwxrwsr-x  3 jpiccola  staff    96B Dec 18 15:40 logs
drwxrws---  2 jpiccola  staff    64B Dec 18 15:40 lost+found
drwxrwsr-x  2 jpiccola  staff    64B Dec 18 15:40 sabnzbd
-rw-rw-r--  1 jpiccola  staff   8.6K Dec 19 08:49 sabnzbd.ini
-rw-rw-r--  1 jpiccola  staff   8.4K Dec 18 15:41 sabnzbd.ini.bak
```
