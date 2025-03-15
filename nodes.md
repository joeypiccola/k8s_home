# tracking

## nodes

| node      | ip         | mac          |
|-----------|------------|--------------|
| control-1 | 10.0.5.201 | 98fa9b5b128d |
| control-2 | 10.0.5.202 | 98fa9b205729 |
| control-3 | 10.0.5.203 | 8c1645ca70b7 |
| control-4 | 10.0.5.204 | e86a643bf337 |
| control-5 | 10.0.5.205 | e86a6432c3f7 |

## load balancer ips

`CiliumLoadBalancerIPPool` = `10.0.5.208/28`

| service                 | ip         | dns               |
|-------------------------|------------|-------------------|
| cilium-gateway-internal | 10.0.5.209 | gateway-api-https |
| cilium-gateway-external | 10.0.5.210 | gateway-external  |
| plex                    | 10.0.5.220 | plex-k8s          |
| home-assistant-x        | 10.0.5.221 | ha-k8s            |
| pihole-dns              | 10.0.5.222 | n/a               |
