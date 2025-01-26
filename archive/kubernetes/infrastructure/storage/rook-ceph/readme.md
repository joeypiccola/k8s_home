# rook-ceph

## notes

Gets dashboard password.

`k -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo`
