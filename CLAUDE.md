# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a GitOps home lab running Kubernetes on Talos Linux (bare metal). ArgoCD manages all workloads via the App of Apps pattern. Secrets are encrypted with SOPS/age and injected at runtime via the 1Password Kubernetes operator + External Secrets.

**Cluster:** `talos` | Domain: `k8s.piccola.us` | VIP: `10.0.5.200` | 5 control-plane nodes: `10.0.5.201-205`

## Git Workflow

**Never run `git commit` or `git push` in this repository.** The user reviews and commits/pushes all changes themselves — stage or prepare edits as needed, but leave committing and pushing to them, always, even if asked to commit elsewhere in a session.

## Required Tools

`kubectl`, `talhelper`, `talosctl`, `helm`, `task`, `sops`, `age`, `yq`, `jq`, `op` (1Password CLI)

## Common Commands

```bash
# List all available tasks
task --list

# Talos cluster operations
task talos:genconfig              # Regenerate node configs (needed after version/config changes)
task talos:apply-config           # Apply configs to all 5 control-plane nodes
task talos:bootstrap              # Bootstrap the cluster (first-time only)
task talos:get-kubeconfig         # Merge kubeconfig (only needed after new talos secrets)
task talos:cordon-and-reboot NODE=<node>  # Safely cordon then reboot a node
task talos:reboot NODE=<node>     # Reboot a node
task talos:reset-node NODE=<node> # Reset and reboot a node (destructive)

# Bootstrap ArgoCD (after fresh cluster)
task install:gateway_api_crds
task install:cilium
task install:argocd
task stage:namespaces             # Apply namespace definitions
task stage:argocd-oci-repos       # Apply ArgoCD OCI repository secrets
task stage:onepassword_secrets    # Requires `op` CLI authenticated
kubectl apply -n argocd -f argocd/aoa_infra.yaml
kubectl apply -n argocd -f argocd/aoa_apps.yaml
kubectl apply -n argocd -f argocd/aoa_storage.yaml

# Useful operational tasks
task argocd:getadminsecret        # Get initial ArgoCD admin password
task argocd:suspend APP=<app>     # Suspend ArgoCD automated sync for an app
task argocd:resume APP=<app>      # Resume ArgoCD automated sync for an app
task stateful:suspend-all         # Suspend sync and scale down all stateful apps to zero
task ha-codeserver:getpassword    # Get Home Assistant code-server password
task restart:media                # Rolling restart all media deployments
task k8s:cordon NODE=<node>       # Cordon a node
task pvc:browse PVC=<name> NS=<ns> # Spin up temp pod to browse/edit a PVC

# SOPS encrypt/decrypt a file
sops -e -i <file>.sops.yaml       # Encrypt in-place
sops -d <file>.sops.yaml          # Decrypt to stdout
```

## Repository Architecture

### `talos/`

Talos Linux configuration managed by `talhelper`.

- `talconfig.yaml` — cluster config template with `${variable}` substitution
- `talenv.yaml` — environment variables (versions, IPs, domain)
- `talsecret.sops.yaml` — SOPS-encrypted cluster secrets (certs, tokens); generated once with `talhelper gensecret`
- `patches/` — machine config patches applied on top of generated configs
- `clusterconfig/` — **generated output** (git-ignored kubeconfig; node YAML files are committed)

Regenerate configs with `task talos:genconfig` whenever `talconfig.yaml`, `talenv.yaml`, or Talos/Kubernetes versions change.

### `argocd/`

ArgoCD App of Apps GitOps structure. Three root App of Apps (apply in this order):

**`aoa_infra.yaml`** → `argocd/aoa_infra/` — Core infrastructure (must install first):

- onepassword (1Password operator), external-secrets, cert-manager, namespace objects

**`aoa_storage.yaml`** → `argocd/aoa_storage/` — Storage layer (after infra):

- Longhorn distributed block storage

**`aoa_apps.yaml`** → `argocd/aoa_apps/` — All other applications:

- `apps/argocd.yaml` — ArgoCD self-manages itself
- `apps/networking/` — Cilium (CNI), cloudflared, pihole, unifi, gateway API, dyndns, cert-manager objects
- `apps/automation/` — Home Assistant, Frigate, ESPHome, EMQX, KMS, doorbell
- `apps/media/` — Plex, Radarr, Sonarr, Sabnzbd, Tautulli, Overseerr
- `apps/monitoring/` — kube-prometheus-stack, Grafana, Goldilocks, Uptime-Kuma, kube-state-metrics, metrics-server, prometheus-node-exporter
- `apps/system/` — NFD, Intel GPU plugin, intel-device-plugins-operator, generic-device-plugin, VPA, Reloader
- `objects/` — PVCs, Gateway API resources, ExternalSecrets, certificates
- `values/` — Helm values files for apps that need them (argocd, cilium, emqx, grafana, kube-prometheus-stack)

Each app YAML under `apps/` is an ArgoCD `Application` resource. Helm values are split out into `values/<app>.yaml` when non-trivial. ArgoCD syncs with `automated: {prune: true, selfHeal: true}` and `serverSideApply: true`.

Frigate's NVR config is inlined in the `frigate-configmap` ConfigMap at `argocd/aoa_apps/objects/frigate/objects.yaml`, under `data.config.yaml` as a literal block scalar indented 4 spaces.

### `bootstrap/`

One-time setup artifacts: secret templates for 1Password operator credentials.

### `scratch/`

Experiments and WIP configs — not applied to the cluster, git-ignored.

## Node Scheduling

**Frigate is pinned to `control-1`.** Frigate has been crashing intermittently and we haven't had time to root-cause it yet; pinning it to its own dedicated node isolates it from resource contention with everything else while that's still unresolved. Pinning is enforced two ways, both intentionally kept as **manual, non-GitOps steps** (not persisted in Talos machine config — they'd need to be reapplied if `control-1` is ever reset/rejoined):

- `kubectl taint nodes control-1 dedicated=frigate:NoSchedule` — keeps every other pod off the node.
- `kubectl label nodes control-1 dedicated=frigate` — paired with a matching `nodeSelector: {dedicated: frigate}` on Frigate (alongside its existing Coral-TPU PCI-feature selector) so Frigate *requires* that node, not just tolerates it.

Frigate's `Application` ([argocd/aoa_apps/apps/automation/frigate.yaml](argocd/aoa_apps/apps/automation/frigate.yaml)) carries the matching `defaultPodOptions.tolerations` entry for the taint.

Because the taint blocks **any** pod without a matching toleration — including DaemonSets — several cluster-wide DaemonSet/controller charts also needed the same toleration added so they keep running on `control-1` (otherwise Frigate itself would break: no CSI plugin means its Longhorn PVCs can't mount, no GPU plugin means its `gpu.intel.com/i915` request can't be satisfied):

- `argocd/aoa_storage/apps/longhorn.yaml` — needs **three** separate keys, not just one: `defaultSettings.taintToleration` (only covers Longhorn's dynamically-managed components — instance-manager, engine-image, share-manager), plus `longhornManager.tolerations` and `longhornDriver.tolerations` (plain Helm-templated tolerations for the `longhorn-manager` DaemonSet and CSI driver-deployer — these are the ones that actually matter and are easy to miss).
- `argocd/aoa_apps/apps/system/intel-device-plugins-gpu.yaml`, `node-feature-discovery.yaml`, `generic-device-plugin.yaml` — each got a plain `tolerations:` (or `worker.tolerations` for NFD) entry.
- Cilium/cilium-envoy already tolerate everything by default — no change needed there.

**Plex, Whisper, and Kokoro preferentially avoid each other's node.** All three are CPU-heavy on a small 5-node cluster (Plex transcoding, Whisper STT, Kokoro TTS), so each carries a `defaultPodOptions.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution` rule (weight 100, `topologyKey: kubernetes.io/hostname`) listing the *other two* app names — soft/"optimistic" rather than a hard requirement, since a hard rule could create scheduling failures once `control-1` is reserved for Frigate and only 4 nodes are left for everything else. This replaced an earlier, now-removed hard anti-affinity scheme (a `stable: "false"` pod label on Frigate that Plex/Home Assistant/ESPHome each hard-avoided) that predates the `control-1` taint and became redundant once the taint took over that job.

## Secrets Management

**SOPS + age:** `.sops.yaml` encrypts files matching `(kubernetes|talos|clusters)/.*\.sops\.ya?ml`. Encrypted fields are matched by regex (passwords, certs, keys, data, stringData). The age private key must be in `SOPS_AGE_KEY` env var (set via git-ignored `.envrc`).

**1Password → External Secrets flow:** The 1Password operator (in `onepassword` namespace) syncs vault items into Kubernetes Secrets. External Secrets resources in `argocd/aoa_apps/objects/` and `argocd/aoa_infra/objects/` reference vault items by name.

## Dependency Updates

Renovate bot (`renovate.json`) auto-updates Helm chart versions in ArgoCD Application YAMLs. Chart versions live in `spec.sources[0].targetRevision` or `spec.source.targetRevision` in the app YAML files.

Auto-merge is enabled for: ArgoCD, Grafana, kube-prometheus-stack, Uptime-Kuma, Reloader, cert-manager, external-secrets, onepassword operator, Goldilocks, VPA, cloudflared, Home Assistant/code-server (7-day minimum age), and the media stack (Plex, Radarr, Sonarr, Sabnzbd — digest/patch updates).

## Cluster Details

| Item | Value |
| ------ | ------- |
| Talos version | `talos/talenv.yaml` → `talosVersion` |
| Kubernetes version | `talos/talenv.yaml` → `kubernetesVersion` |
| Control plane nodes | `control-1` through `control-5` at `10.0.5.201-205` |
| VIP | `10.0.5.200` |
| LB IP pool | `10.0.5.208/28` (CiliumLoadBalancerIPPool) |
| Key LB IPs | gateway-internal: `.209`, gateway-external: `.210`, emqx: `.219`, plex: `.220`, pihole-dns: `.222` |
| DNS servers | `10.0.3.24`, `10.0.3.22` (PiHole instances) |
| IP/network docs | `ipam.md` |
