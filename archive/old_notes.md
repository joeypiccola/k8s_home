
### Build the infrastructure with Terraform

Leverages git ignored `.envrc` to set environment variables for vCenter authentication.

```shell
# terraform/.envrc
export VSPHERE_USER=''
export VSPHERE_PASSWORD=''
export VSPHERE_SERVER=''
export VSPHERE_ALLOW_UNVERIFIED_SSL='true'
```

Terraform will create VMs leveraging Talos' VMware OVA specific image. The Talos version is dynamically parsed from `talenv.yaml`. Each VM built is passed its specific Talos config via VMware's `guestinfo` mechanism. At boot, Talos knows to grab the config from `guestinfo.talos.config`.

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
talosctl bootstrap --nodes 10.0.5.151
```

At this point, Talos will form an etcd cluster, and start the Kubernetes control plane components. This will take a few minutes. Once complete, if this is a new cluster with new generated secrets via `talhelper gensecret` you can run the following to download your Kubernetes client configuration and get started. Running this command will add (merge) you new cluster into your local Kubernetes configuration.

`talosctl kubeconfig --nodes 10.0.5.151 --endpoints 10.0.5.151`

#### Create and apply talos-vmtoolsd-config secret

This secret is used by the `talos-vmtoolsd` daemonset (that we patched in during talos node config generation). Without it, these pods will be stuck in `ContainerCreating`. Again, this is full `talosconfig` that is written to the secret. More info on this back in [VMware Tools](#vmware-tools).

todo(joey): this is not great. sharing same talosconfig we use to admin the cluster with the vmtoolsd daemonset.

```shell
# from repo root
cd talos/clusterconfig
talosctl -n 10.0.5.151 config new talosconfig_vmtoolsd.yaml --roles os:admin
kubectl -n kube-system create secret generic talos-vmtoolsd-config --from-file=talosconfig=./talosconfig_vmtoolsd.yaml
rm ./talosconfig_vmtoolsd.yaml
```

#### Patch control plane machines with admission control (WIP)

For this to work `control-1.piccola.us` names must be in DNS. "That is what allows you to run privileges in all namespaces", move away from this using a kyverno policy.

```shell
# from repo root
cd talos/clusterconfig
talosctl patch machineconfig -n control-1.piccola.us,control-2.piccola.us,control-3.piccola.us,control-4.piccola.us,control-5.piccola.us --patch-file ../patches/admissionControl-patch.yaml
```

#### talosctl commands

Running from somewhere with a valid TALOSCONFIG env var.

```plaintext
talosctl dashboard
talosctl memory
```

### Bootstrap the cluster (cilium)

First install Gateway API's CRDs. This is a [requirement](https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/#prerequisites) of cilium when `gatewayAPI.enabled=true`.

```bash
# k apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
# k apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
# kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/experimental-install.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml

```

```bash
# from repo root # 1.16.1
cilium_helm_release=$(yq '.spec.sources[0].targetRevision' argocd/apps/cilium.yaml)
helm repo add cilium https://helm.cilium.io/
helm repo update cilium
helm template cilium cilium/cilium --version $cilium_helm_release --namespace kube-system --values ./argocd/helm_values/cilium.yaml | kubectl apply -f -
    # --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    # --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    # --set ipam.mode=kubernetes \
    # --set cgroup.autoMount.enabled=false \
    # --set cgroup.hostRoot=/sys/fs/cgroup \
    # --set kubeProxyReplacement=true \
    # --set gatewayAPI.enabled=true \
    # --set bgpControlPlane.enabled=true \
    # --set bgp.announce.loadbalancerIP=true \
    # --set l7Proxy=true \
    # --set k8sServiceHost=localhost \
    # --set k8sServicePort=7445 | kubectl apply -f -

# # 1.15.8
# helm template cilium cilium/cilium \
#     --version $cilium_helm_release \
#     --namespace kube-system \
#     --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
#     --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
#     --set ipam.mode=kubernetes \
#     --set cgroup.autoMount.enabled=false \
#     --set cgroup.hostRoot=/sys/fs/cgroup \
#     --set kubeProxyReplacement=true \
#     --set gatewayAPI.enabled=true \
#     --set bgpControlPlane.enabled=true \
#     --set bgp.announce.loadbalancerIP=true \
#     --set l7Proxy=true \
#     --set k8sServiceHost=localhost \
#     --set k8sServicePort=7445 | kubectl apply -f -

# # l2
# cilium_helm_release=$(yq '.spec.source.targetRevision' argocd/apps/cilium.yaml)
# helm repo add cilium https://helm.cilium.io/
# helm repo update cilium
# # 1.15.8
# helm template cilium cilium/cilium \
#     --version $cilium_helm_release \
#     --namespace kube-system \
#     --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
#     --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
#     --set ipam.mode=kubernetes \
#     --set cgroup.autoMount.enabled=false \
#     --set cgroup.hostRoot=/sys/fs/cgroup \
#     --set kubeProxyReplacement=true \
#     --set gatewayAPI.enabled=true \
#     --set externalIPs.enabled=true \
#     --set l7Proxy=true \
#     --set l2announcements.enabled=true \
#     --set devices=eth0 \
#     --set k8sServiceHost=localhost \
#     --set k8sServicePort=7445 | kubectl apply -f -

# # 1.16.1
# helm template cilium cilium/cilium \
#     --version $cilium_helm_release \
#     --namespace kube-system \
#     --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
#     --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
#     --set ipam.mode=kubernetes \
#     --set cgroup.autoMount.enabled=false \
#     --set cgroup.hostRoot=/sys/fs/cgroup \
#     --set kubeProxyReplacement=true \
#     --set gatewayAPI.enabled=true \
#     --set l7Proxy=true \
#     --set k8sServiceHost=localhost \
#     --set bgpControlPlane.enabled=true \
#     --set bgp.announce.loadbalancerIP=true \
#     --set k8sServicePort=7445 | kubectl apply -f -
    # --set bpf.masquerade=true \
    # --set bpf.tproxy=true \
    # --set autoDirectNodeRoutes=true \
    # --set ipv4NativeRoutingCIDR='10.244.0.0/16' \
    # --set operator.rollOutPods=true \
    # --set localRedirectPolicy=true \
    # --set rollOutCiliumPods=false \
    # --set routingMode=native \
    # --set externalIPs.enabled=true \
    # --set gatewayAPI.gatewayClass.create=true \

    # u removed these on dec 10
        # --set k8sClientRateLimit.qps={QPS} \
    # --set k8sClientRateLimit.burst={BURST} \
```

The demo app

```bash
k apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/bookinfo/platform/kube/bookinfo.yaml
k apply -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/gateway/basic-http.yaml
```

### Bootstrap the cluster (argoCD)

Once the cluster is up create argo namespace.

```plaintext
kubectl create namespace argocd
kubectl config set-context --current --namespace=argocd
```

Use helm to imperatively install argo.

```bash
# from repo root
argo_helm_release=$(yq '.spec.sources[0].targetRevision' argocd/apps/argocd.yaml)
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm template argocd argo/argo-cd --version $argo_helm_release --namespace argocd --values ./argocd/helm_values/argocd.yaml | kubectl apply -f -
```

The following is optional if you want to view the argo dashboard before ingress setup.

```bash
# get the argo password
argocd admin initial-password -n argocd
# create a port forward to `argocd-server` pod
# login
argocd login localhost:8080 --username admin
# update the password
argocd account update-password
```

Stage 1Password secrets. Requires files in `./bootstrap`.

```bash
# from repo root
# get the 1password cred file from 1password
onepass_creds_b64=$(op document get 'talos Credentials File' | base64)
# get the 1password access token from 1password
onepass_token=$(op item get 'talos Access Token Kubernetes operator' --format json --fields credential | jq -r .value)
# parse the specified helm release version from the one password argo application (note: this prepends the parsed version with "connect-")
onepass_helm_release=connect-$(yq '.spec.source.targetRevision' argocd/infra/onepassword.yaml)
# create the onepassword namespace (we're about to create secrets in this namespace)
k create namespace onepassword
# substitute in 1password token and helm release version into onepassword-token.yaml secret and apply it to k8s
onepass_token=$onepass_token onepass_helm_release=$onepass_helm_release yq '.stringData.token = env(onepass_token), .metadata.labels."helm.sh/chart" = env(onepass_helm_release)' ./bootstrap/onepassword-token.yaml | k apply -f -
# substitute in 1password base64 cred file and helm release version into op-credentials.yaml secret and apply it to k8s
onepass_creds_b64=$onepass_creds_b64 onepass_helm_release=$onepass_helm_release yq '.stringData."1password-credentials.json" = env(onepass_creds_b64), .metadata.labels."helm.sh/chart" = env(onepass_helm_release)' ./bootstrap/op-credentials.yaml | k apply -f -
```

Kick off the app of apps

```bash
# from repo root
k apply -n argocd -f argocd/app-of-apps-infra.yaml
k apply -n argocd -f argocd/app-of-apps.yaml
```

## Scratch

```bash
cd scratch/cilium
k create ns test
k apply -f deployment.yaml
k apply -f service2.yaml
k apply -f pool.yaml
k apply -f bgp_peer.yaml
k apply -f gateway.yaml
k apply -f route.yaml
```

```bash
kubectl create namespace onepassword
helm template connect 1password/connect --include-crds -n onepassword --version 1.17.0 --set operator.create=true --set operator.token.value=$onepass_token --set connect.credentials_base64=$onepass_creds_b64 | kubectl apply -f -
helm template connect 1password/connect -n onepassword --version 1.17.0 --set operator.create=true --set operator.token.value=$onepass_token --set connect.credentials_base64=$onepass_creds_b64 >> connect.yaml
helm template connect 1password/connect -n onepassword --version 1.17.0 --set operator.create=true --set operator.token.value=$onepass_token --set-file connect.credentials=1password-credentials.json >> connect2.yaml
# stringData:
#   1password-credentials.json
```


kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml




kubectl label ns longhorn-system pod-security.kubernetes.io/enforce=privileged


Readiness probe failed: Get "https://10.244.2.211:9501/v1/healthz": dial tcp 10.244.2.211:9501: connect: connection refused




pre-pull-share-manager-image share-manager image pulled
longhorn-manager time="2024-09-13T05:31:12Z" level=fatal msg="Error starting manager: failed to check environment,

please make sure you have iscsiadm/open-iscsi installed on the host:
failed to execute: /usr/bin/nsenter [nsenter --mount=/host/proc/6240/ns/mnt --net=/host/proc/6240/ns/net iscsiadm --version], output , stderr nsenter: failed to execute iscsiadm: No such file or directory\n: exit status 127" func=main.main.DaemonCmd.func3 file="daemon.go:94"
Stream closed EOF for longhorn-system/longhorn-manager-mxpgl (longhorn-manager)


# talos and longhorn docs
https://hackmd.io/@QI-AN/Install-Longhorn-on-Talos-Kubernetes?utm_source=preview-mode&utm_medium=rec
https://longhorn.io/docs/1.7.0/advanced-resources/os-distro-specific/talos-linux-support/


talosctl -n 10.0.5.151 disks
NODE         DEV        MODEL          SERIAL   TYPE   UUID   WWID                                   MODALIAS      NAME   SIZE    BUS_PATH                                                           SUBSYSTEM          READ_ONLY   SYSTEM_DISK
10.0.5.151   /dev/sda   Virtual disk   -        HDD    -      naa.6000c29d41ac6001c9a1038c2b1a5ca6   scsi:t-0x00   -      64 GB   /pci0000:00/0000:00:15.0/0000:03:00.0/host2/target2:0:0/2:0:0:0/   /sys/class/block               *
10.0.5.151   /dev/sdb   Virtual disk   -        HDD    -      naa.6000c29b0f60829ed0295ed9a20e75d3   scsi:t-0x00   -      86 GB   /pci0000:00/0000:00:15.0/0000:03:00.0/host2/target2:0:1/2:0:1:0/   /sys/class/block




➜ talosctl mounts -n 10.0.5.151 | grep long
10.0.5.151   /dev/sdb1    79.93      0.59       79.34           0.74%          /var/mnt/longhorn
10.0.5.151   tmpfs        16.45      0.00       16.45           0.00%          /var/lib/kubelet/pods/734f21eb-a747-48bc-a640-b459dcb875b3/volumes/kubernetes.io~secret/longhorn-grpc-tls
10.0.5.151   tmpfs        16.45      0.00       16.45           0.00%          /var/lib/kubelet/pods/7da6d7e1-c9c4-41d8-ba5c-8c497429106f/volumes/kubernetes.io~secret/longhorn-grpc-tls


# removed from talconfig on dec 1
  # - hostname: control-4.${domainName}
  #   installDisk: /dev/sda
  #   ipAddress: ${controlPlaneIP_4}
  #   controlPlane: true
  #   nameservers:
  #     - ${ns1}
  #     - ${ns2}
  #   networkInterfaces:
  #     - interface: eth0
  #       vip:
  #         ip: ${vip}
  #       dhcp: false
  #       addresses:
  #         - ${controlPlaneIP_4}/24
  #       routes:
  #         - network: 0.0.0.0/0
  #           gateway: ${gateway}
  # - hostname: control-5.${domainName}
  #   installDisk: /dev/sda
  #   ipAddress: ${controlPlaneIP_5}
  #   controlPlane: true
  #   nameservers:
  #     - ${ns1}
  #     - ${ns2}
  #   networkInterfaces:
  #     - interface: eth0
  #       vip:
  #         ip: ${vip}
  #       dhcp: false
  #       addresses:
  #         - ${controlPlaneIP_5}/24
  #       routes:
  #         - network: 0.0.0.0/0
  #           gateway: ${gateway}


EdgeRouter BGP

set protocols bgp 64501 neighbor 10.0.5.201 remote-as 64502
set protocols bgp 64501 neighbor 10.0.5.202 remote-as 64502
set protocols bgp 64501 neighbor 10.0.5.203 remote-as 64502
set protocols bgp 64501 neighbor 10.0.5.204 remote-as 64502
set protocols bgp 64501 neighbor 10.0.5.205 remote-as 64502
commit; exit

delete protocols bgp 64501 neighbor 10.0.5.151 remote-as 64502
delete protocols bgp 64501 neighbor 10.0.5.152 remote-as 64502
delete protocols bgp 64501 neighbor 10.0.5.153 remote-as 64502
delete protocols bgp 64501 neighbor 10.0.5.154 remote-as 64502
delete protocols bgp 64501 neighbor 10.0.5.155 remote-as 64502
commit; exit

show ip route

exit

```
│ grafana logger=cleanup t=2025-02-20T06:40:28.13943938Z level=info msg="Completed cleanup jobs" duration=59.677819ms                                                                                  │
│ grafana logger=server t=2025-02-20T06:42:49.866565699Z level=info msg="Shutdown started" reason="System signal: terminated"                                                                          │
│ grafana logger=ticker t=2025-02-20T06:42:49.866608997Z level=info msg=stopped last_tick=2025-02-20T06:42:40Z                                                                                         │
│ grafana logger=tracing t=2025-02-20T06:42:49.866686763Z level=info msg="Closing tracing"                                                                                                             │
│ grafana logger=grafana-apiserver t=2025-02-20T06:42:49.866780857Z level=info msg="StorageObjectCountTracker pruner is exiting"
```



helm search repo grafana/grafana
helm show values grafana/grafana --version 8.10.0 >> ./scratch/charts/grafana.yaml
