# kubernetes @ home

Kubernetes on bare metal using [Talos Linux](https://www.talos.dev/). GitOps managed by [ArgoCD](https://argo-cd.readthedocs.io/) via the App of Apps pattern. Secrets encrypted with [SOPS](https://github.com/getsops/sops)/[age](https://github.com/FiloSottile/age) and injected at runtime via the [1Password Kubernetes operator](https://developer.1password.com/docs/k8s/k8s-operator/) + [External Secrets](https://external-secrets.io/).

|                |                                                     |
|----------------|-----------------------------------------------------|
| **Cluster**    | `talos`                                             |
| **Domain**     | `k8s.piccola.us`                                    |
| **VIP**        | `10.0.5.200`                                        |
| **Nodes**      | `control-1` through `control-5` at `10.0.5.201-205` |
| **Talos**      | see `talos/talenv.yaml`                             |
| **Kubernetes** | see `talos/talenv.yaml`                             |

## Common Maintenance Tasks

### Media

```bash
task restart:media                          # Rolling restart all media deployments
```

### ArgoCD App Control

```bash
task argocd:suspend APP=<app>               # Suspend automated sync for an app
task argocd:resume APP=<app>                # Resume automated sync for an app
```

### Stateful Apps

```bash
task stateful:suspend-all                   # Suspend sync and scale down all stateful apps
task stateful:resume-all                    # Resume sync and scale up all stateful apps
```

### PVC Browsing

```bash
task pvc:browse PVC=<name> NS=<namespace>   # Spin up a temp pod to browse/edit a PVC
```

### Cilium

Cilium is the CNI for this cluster. Upgrades require care — see [docs/cilium-upgrades.md](docs/cilium-upgrades.md) for the full procedure.

### Node Maintenance

```bash
task talos:cordon-and-reboot NODE=control-1  # Cordon, drain, then reboot a node
```

### Passwords / Secrets

```bash
task argocd:getadminsecret                  # Get the initial ArgoCD admin password
task ha-codeserver:getpassword              # Get the Home Assistant code-server password
```

---

## Prerequisites

- `kubectl`
- `talhelper`
- `talosctl`
- `helm`
- `task`
- `sops`
- `age`
- `yq`
- `jq`
- `op` (1Password CLI)

## Talos

[Talos Linux](https://www.talos.dev/) is a minimal, immutable, API-driven OS purpose-built for Kubernetes. There is no SSH — all management is via `talosctl`.

### Versions

Talos and Kubernetes versions are interdependent. Refer to the [support matrix](https://www.talos.dev/latest/introduction/support-matrix/) for compatible pairs. Versions are set in `talos/talenv.yaml` and used throughout the config generation process.

- Talos releases: [github.com/siderolabs/talos/releases](https://github.com/siderolabs/talos/releases)
- Kubernetes releases: [kubernetes.io/releases](https://kubernetes.io/releases/)

### Config Files

[`talhelper`](https://github.com/budimanjojo/talhelper) generates per-node Talos configs from three source files:

| File                        | Purpose                                              |
|-----------------------------|------------------------------------------------------|
| `talos/talconfig.yaml`      | Config template with `${variable}` substitution      |
| `talos/talenv.yaml`         | Variable values (versions, IPs, domain)              |
| `talos/talsecret.sops.yaml` | SOPS-encrypted cluster secrets (certs, tokens, keys) |

`talsecret.sops.yaml` was generated once with `talhelper gensecret > talos/talsecret.sops.yaml` and then encrypted in-place. It should never need to be regenerated unless starting fresh.

Output configs land in `talos/clusterconfig/` (node YAMLs are committed; `kubeconfig` is git-ignored).

### Regenerating Configs

Regenerate configs whenever Talos version, Kubernetes version, or any config setting changes:

```bash
task talos:genconfig
```

### SOPS + age

`talsecret.sops.yaml` is encrypted with SOPS using an age key. The age key must be available as `SOPS_AGE_KEY` in your environment. This is set via the git-ignored `.envrc` at the repo root:

```bash
# .envrc
export SOPS_AGE_KEY=AGE-SECRET-KEY-...
```

The `.sops.yaml` at the repo root defines which file paths and which keys within those files are in scope for encryption. To encrypt a new secrets file:

```bash
sops -e -i path/to/file.sops.yaml
```

The VSCode extension `signageos.signageos-vscode-sops` handles transparent encrypt/decrypt on save when `SOPS_AGE_KEY` is set.

---

## Rebuild from Scratch

### Scenario 1 — Nodes are responsive, intentional rebuild

#### 1. Suspend stateful apps and back up volumes

```bash
task stateful:suspend-all
```

Then open the Longhorn UI and trigger an immediate backup (run the daily backup job manually).

#### 2. Reset and wipe nodes

```bash
task talos:reset-node NODE=all
task talos:wipe-nvme
```

#### 3. PXE boot nodes

Not covered here.

#### 4. Regenerate configs if needed

Update `talhelper` and `talosctl` first if versions have changed.

```bash
task talos:genconfig
```

#### 5. Apply configs

```bash
task talos:apply-config
```

#### 6. Bootstrap the cluster

```bash
task talos:bootstrap
```

#### 7. Get kubeconfig

Only required when new Talos secrets were generated.

```bash
task talos:get-kubeconfig
```

#### 8. Install core infrastructure

Cilium and ArgoCD are bootstrapped manually here and will be self-managed by ArgoCD afterward.

```bash
task install:gateway_api_crds
task install:cilium          # wait for pods to be ready
task install:argocd
task stage:onepassword_secrets
```

#### 9. Stage namespaces

Prevents eventual-consistency delays for apps that depend on namespace labels.

```bash
task stage:namespaces
```

#### 10. Apply ArgoCD App of Apps — infra

Installs: 1Password operator, External Secrets, cert-manager.

```bash
kubectl apply -n argocd -f argocd/aoa_infra.yaml
```

#### 11. Apply ArgoCD App of Apps — storage

Installs: Longhorn.

```bash
kubectl apply -n argocd -f argocd/aoa_storage.yaml
```

#### 12. Restore Longhorn volumes

With Longhorn running, open the UI (port-forward if needed) and restore volumes from backup:

1. Clean up any orphaned data: **Settings → Orphaned Data**
2. Restore each volume, checking **Use Previous Name**
3. For each restored volume, go to **Create PV/PVC**, check **Create PVC** and **Use Previous PVC**

#### 13. Apply ArgoCD App of Apps — apps

```bash
kubectl apply -n argocd -f argocd/aoa_apps.yaml
```
