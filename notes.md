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
