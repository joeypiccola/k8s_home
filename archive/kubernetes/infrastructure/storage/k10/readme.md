# k10

## dashbaord

Gets a dashbaoard login token.

`k --namespace kasten-io create token k10-k10 --duration=24h`

## how to restore

Beginning with a new cluster from scratch. Assumes k10 is installed and configured with previous profiles and policies (e.g. the `disaster-recovery` profile). Start by installing the k10-restore chart. Upon doing this you'll see in the k10 dashboard a restore is in process.

```bash
# helm repo add kasten https://charts.kasten.io # if not already done
helm repo update kasten
helm install k10-restore kasten/k10restore --namespace=kasten-io --set sourceClusterID=<cluster-id> --set profile.name=disaster-recovery
```

Using pihole's an example, in order to restore the PVC you first must scale the existing deployment to zero.

`k scale deployment pihole --replicas 1 -n pihole`

Once complete, you can then restore the PVC via the k10 dashboard. When complete, you can then scale the deployment back up.

`k scale deployment pihole --replicas 1 -n pihole`

When done, you can then uninstall the k10-restore chart.

`helm uninstall k10-restore --namespace=kasten-io`
