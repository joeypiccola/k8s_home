# ipam

## nodes - main

`talos.k8s.piccola.us = 10.0.5.200`

| node      | ip         | mac          | node                     |
|-----------|------------|--------------|--------------------------|
| control-1 | 10.0.5.201 | 98fa9b5b128d | control-1.k8s.piccola.us |
| control-2 | 10.0.5.202 | 98fa9b205729 | control-2.k8s.piccola.us |
| control-3 | 10.0.5.203 | 8c1645ca70b7 | control-3.k8s.piccola.us |
| control-4 | 10.0.5.204 | e86a643bf337 | control-4.k8s.piccola.us |
| control-5 | 10.0.5.205 | e86a6432c3f7 | control-5.k8s.piccola.us |

## load balancer ips - main

`CiliumLoadBalancerIPPool` = `10.0.5.208/28` (208-223)

| service                      | ip         | dns               |
|------------------------------|------------|-------------------|
| cilium-gateway-internal      | 10.0.5.209 | gateway-api-https |
| cilium-gateway-external      | 10.0.5.210 | n/a               |
| kms                          | 10.0.5.217 | n/a               |
| cilium-gateway-unifi-gateway | 10.0.5.218 | gateway-api-unifi |
| emqx                         | 10.0.5.219 | n/a               |
| plex                         | 10.0.5.220 | plex-k8s          |
| pihole-dns                   | 10.0.5.222 | n/a               |

## esphome

| device                  | ip            | static |
|-------------------------|---------------|--------|
| joey-office-esp         | 192.168.9.151 | true   |
| master-blindcontrol-esp | 192.168.9.152 | true   |
| mech-room-esp           | 192.168.9.153 | true   |
| garage-esp              | 192.168.9.154 | true   |
| basement-esp            | 192.168.9.155 | true   |

## sonos

| device   | ip         | reservation |
|----------|------------|-------------|
| backyard | 10.0.3.71  | true        |
| basement | 10.0.3.63  | true        |
| garage   | 10.0.3.61  | true        |
| kitchen  | 10.0.3.103 | true        |
| master   | 10.0.3.109 | true        |

## access points

| device    | ip         | reservation |
|-----------|------------|-------------|
| ap-house  | 10.0.2.50  | true        |
| ap-garage | 10.0.2.100 | true        |
