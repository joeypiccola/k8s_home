# Notes

## Tools

### Helm

```bash
# List current repos
helm repo list

# Update a specific repo
helm repo update argo

# List all charts in a repo
helm search repo argo

# List all versions of a chart
helm search repo argo/argo-cd --versions

# Show default values for a specific chart version
helm show values argo/argo-cd --version 7.4.1 >> ./argo-cd_7.4.1.yaml
```

### MongoDB

```bash
# Log in as root
mongosh "mongodb://root:<pw>@localhost:27017"

# Select a database
use admin
use unifi

# List users
db.getUsers()
```

## Operations

### Node Crash Recovery

1. Unplug the node
2. Plug in the node
3. Power on
4. Things will reconcile and either come back up or move to another node

## References

### NixOS

https://www.youtube.com/watch?v=63sSGuclBn0

boot from minimal installer and `sudo -i`

then get in fdisk for the nvme disk `fdisk /dev/nvme0n1`, you can do `fdisk -l` to see the disks

then  `g` to create new gpt label, enter
then `n` to set partition number, enter
then enter to accept first sector
then +500M for partition size, enter
then at new help screen type `t` enter
then `1` to set partitaoni 1 to UEFI
