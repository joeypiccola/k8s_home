# Cilium Upgrades

Cilium upgrades must be performed manually to avoid disruption. Renovate opens PRs for version bumps but those PRs must not be merged until after the in-cluster upgrade is complete.

## Procedure

### 1. Run preflight checks

Follow the preflight check steps from the [Cilium upgrade docs](https://docs.cilium.io/en/stable/operations/upgrade/) before proceeding. Only continue if all checks pass.

### 2. Disable Renovate

Set `"enabled": false` in [renovate.json](../renovate.json) to prevent any auto-merges during the upgrade window. When Renovate auto-merges a PR for any ArgoCD app with `automerge` enabled, it triggers a reconciliation of the parent `aoa-apps` App of Apps — which will unsuspend the Cilium app we're about to suspend. If that happens mid-upgrade, ArgoCD will attempt to downgrade Cilium back to the version in Git.

### 3. Suspend the ArgoCD Cilium application

```bash
task argocd:suspend APP=cilium
```

This prevents ArgoCD from reconciling (and reverting) the in-cluster changes while the upgrade is in progress.

### 4. Template the upgraded Cilium manifests

Use `helm template` to render the new version with the `upgradeCompatibility` flag set to the current running version. This minimizes datapath disruption as described in the Cilium upgrade docs. Consult the [Cilium upgrade docs](https://docs.cilium.io/en/stable/operations/upgrade/) to ensure this is correct.

```bash
helm template cilium oci://quay.io/cilium/charts/cilium --version <new-version> \
  --namespace kube-system \
  --set upgradeCompatibility=<current-version> \
  -f argocd/aoa_apps/values/cilium.yaml \
  > cilium.yaml
```

Example (upgrading to 1.19.3 from 1.19.2):

```bash
helm template cilium oci://quay.io/cilium/charts/cilium --version 1.19.3 \
  --namespace kube-system \
  --set upgradeCompatibility=1.19.2 \
  -f argocd/aoa_apps/values/cilium.yaml \
  > cilium.yaml
```

### 5. Apply and wait for rollout

```bash
kubectl apply -f cilium.yaml
```

Wait for the rollout to complete before proceeding:

```bash
kubectl rollout status daemonset/cilium -n kube-system
kubectl rollout status deployment/cilium-operator -n kube-system
```

### 6. Merge the Renovate PR

Merge the Renovate-generated PR that bumps the Cilium chart version in ArgoCD. This brings the GitOps state in sync with the now-upgraded in-cluster version.

Verify ArgoCD sees the app as **Synced** after reconciliation before continuing.

### 7. Resume the ArgoCD Cilium application

```bash
task argocd:resume APP=cilium
```

### 8. Re-enable Renovate

Remove or revert the `"enabled": false` change in [renovate.json](../renovate.json).
