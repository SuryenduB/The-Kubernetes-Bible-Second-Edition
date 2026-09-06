# NFS Provisioner Recovery — 2026-09-06

## Symptom

The Helm-managed `nfs-provisioner` pod entered `CreateContainerError` because kubelet
could not stat its projected NFS mount:

```text
stale NFS file handle
```

The provisioner itself was not the source of the stale handle; the node-local pod
mount state was stale.

## Recovery performed

The affected pod was deleted and allowed to be recreated by its ReplicaSet:

```bash
kubectl delete pod -n default \
  nfs-provisioner-nfs-subdir-external-provisioner-54bd4c4887cmjqr \
  --wait=true
```

The replacement pod became `1/1 Running`, acquired the leader lease, and successfully
mounted the NFS export. No StorageClass, PVC, or NFS data was deleted.

## Verification

```bash
kubectl get pod -n default -l app=nfs-provisioner -o wide
kubectl get events -n default --sort-by=.lastTimestamp
```

The replacement pod was:

```text
nfs-provisioner-nfs-subdir-external-provisioner-54bd4c4887bstwx  1/1  Running
```

The deployment is Helm-managed (`nfs-provisioner`); the durable source of truth is
the Helm release, not a repository manifest. If stale handles recur on the same
node, inspect node/NFS health and recreate only the affected provisioner pod.
