# random notes

## tools

### helm

list current repos

`helm repo list`

update a specific repo (e.g. argo)

`helm repo update argo`

list all charts in a repo (e.g. argo)

`helm search repo argo`

list all versions of a chart in a repo (e.g. argo/argo-cd)

`helm search repo argo/argo-cd --versions`

list latest versions of a chart in a repo (e.g. argo/argo-cd)

`helm search repo argo/argo-cd --versions`

show default values for a specific chart version

`helm show values argo/argo-cd --version 7.4.1 >> ./argo-cd_7.4.1.yaml`

### mongodb

logon as root

`mongosh "mongodb://root:<pw>@localhost:27017"`

select a database

`use admin`
`use unifi`

list users

`db.getUsers()`

### frigate

## node crash

unplug node
plug in node
power on
things will reconcile and either come back up or move to another node


### nixos

https://www.youtube.com/watch?v=63sSGuclBn0

boot from minimal installer and `sudo -i`

then get in fdisk for the nvme disk `fdisk /dev/nvme0n1`, you can do `fdisk -l` to see the disks

then  `g` to create new gpt label, enter
then `n` to set partition number, enter
then enter to accept first sector
then +500M for partition size, enter
then at new help screen type `t` enter
then `1` to set partitaoni 1 to UEFI
