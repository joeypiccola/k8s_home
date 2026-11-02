# Talos config (topf)

This directory is the source of truth for the Talos machine config on the `talos` cluster: five control-plane nodes, `control-1` to `control-5`. It's managed with [topf](https://github.com/postfinance/topf), which replaced the archived talhelper.

topf builds each node's config from `topf.yaml`, the secrets bundle and the patches here, compares it with what the node is running, and applies any differences.

## Layout

| Path | Purpose | In git |
|---|---|---|
| `topf.yaml` | Cluster name, endpoint, Talos and Kubernetes versions, node list | Yes |
| `schematic.yaml` | Image Factory system extensions, which determine the installer image | Yes |
| `secrets.sops.yaml` | SOPS-encrypted cluster secrets (CAs, tokens) | Yes |
| `all/` | Patches for every node | Yes |
| `control-plane/` | Patches for control-plane nodes | Yes |
| `node/<host>/` | Patches for a single node | Yes |
| `output/` | Rendered configs from `topf render`, which contain **plaintext secrets** | No |
| `talosconfig` | Client credentials for `talosctl` | No |

## How a node's config is built

Patches merge in this order, and later patches override earlier ones:

1. `all/`
2. `control-plane/` (the node's role)
3. `node/<host>/` (per-node overrides)

Within a folder, patches apply in filename order. `.yaml.tpl` files are Go templates with access to values like `{{ .Node.Host }}` and `{{ .Node.IP }}`.

| Patch | Sets |
|---|---|
| `all/00-install-disk.yaml` | Install disk |
| `all/01-hostname.yaml.tpl` | Hostname, taken from `host` in `topf.yaml` |
| `all/02-resolvers.yaml` | DNS servers |
| `all/03-network.yaml.tpl` | Node IP, gateway and the VIP on `eno1` |
| `all/04-machine.yaml` | Kernel modules, Longhorn mount and user volume |
| `control-plane/01-cluster.yaml` | No CNI or kube-proxy (Cilium replaces both), workloads allowed on control-plane nodes |
| `node/control-1.k8s.piccola.us/00-frigate.yaml` | `dedicated=frigate` label and `NoSchedule` taint that reserve `control-1` for Frigate |

## Requirements

- `topf`, `talosctl`, `sops` and `task`
- `SOPS_AGE_KEY` set, so topf can decrypt the secrets bundle
- A local `talosconfig` for the `talosctl` tasks, which a fresh clone won't have:

  ```bash
  # from talos/topf
  topf talosconfig > talosconfig
  ```

## Making a change

Edit the relevant file, then roll it out one node at a time from the repo root:

```bash
task talos:diff
task talos:apply-config NODES='^control-5\.' MODE=no-reboot
```

- **`task talos:diff`** changes nothing. It reports a failure when changes are pending because topf exits 2, which is expected.
- **`MODE=no-reboot`** makes a change that needs a reboot fail instead of rebooting the node.
- **`NODES`** is a regex matched against `host`. Without it, the task targets every node, and the default `auto` mode can reboot them.
- **Leave `control-1` until last.** It's the dedicated Frigate node.

## Warnings

- **Never regenerate `secrets.sops.yaml`.** It must match the running cluster, so answer no if topf offers to generate new secrets.
- **Don't change the `host` values.** They set the hostnames, and through them the Kubernetes node names.
- **Don't commit `output/` or `talosconfig`,** and don't share the output of `topf secrets`, which isn't redacted. Both paths are git-ignored here.
- **Deleting the Frigate patch removes the taint and label.** Talos owns `dedicated=frigate` on `control-1` once the patch is applied, so taking it out of the config also takes it off the node.
- **Check `control-1` after a rebuild.** The taint can arrive shortly after the node registers, and `NoSchedule` doesn't evict pods that already landed there. List them with `kubectl get pods -A --field-selector spec.nodeName=control-1` and delete any that don't belong.

## DNS

Nodes use `10.0.3.170` as the primary and `8.8.8.8` as a brief backup while the primary is being patched. `8.8.8.8` doesn't know internal names, so these won't resolve during that window. Keep it short, and avoid rebooting nodes or making cluster changes until the primary is back.

## Not yet tested

These are documented by topf but haven't been run on this cluster:

- **Bootstrap:** `task talos:bootstrap` needs confirming on the next rebuild.
- **Upgrades:** the plan is to change the version in `topf.yaml`, then use `topf upgrade`, which supports `--dry-run`. See the [upgrade docs](https://github.com/postfinance/topf/blob/main/docs/commands/upgrade.md) and [Kubernetes upgrade docs](https://github.com/postfinance/topf/blob/main/docs/kubernetes-upgrade.md).
- **Talos 1.14:** `all/00-install-disk.yaml` must move from `machine.install` to `UnattendedInstallConfig` as part of that upgrade, because a node rejects a config with both.

## Further reading

- [topf documentation](https://postfinance.github.io/topf/)
- [Talos machine config reference](https://www.talos.dev/)
