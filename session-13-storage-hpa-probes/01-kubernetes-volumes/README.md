# Kubernetes Volumes

What I learned about storage in Kubernetes, with the examples I ran on minikube. The YAML files used are
in [01-volumes](../01-volumes), [02-persistent-storage](../02-persistent-storage) and
[03-storageclass](../03-storageclass). Screenshots are in [../screenshots](../screenshots).

## Why volumes?

A container's filesystem lives only as long as that container. When the container restarts, anything it
wrote is gone. A **volume** is a directory that Kubernetes mounts into the container. Where that directory
actually lives decides how long the data survives:

| Type | Where the data lives | Survives container restart | Survives Pod delete | Survives node loss |
|------|----------------------|:--:|:--:|:--:|
| `emptyDir` | node disk (or RAM), created with the Pod | yes | **no** | no |
| `hostPath` | a fixed directory on the node | yes | yes (same node only) | no |
| PVC → PV | storage managed by the cluster (disk, NFS, EBS, ...) | yes | **yes** | depends on the backend |

---

## 1. `emptyDir`

An empty directory that is created when the Pod is scheduled and deleted when the Pod is removed. Every
container in the Pod can mount it, so it is a common way to share files between a main container and a
sidecar, or to hold scratch/cache data.

```yaml
# 01-volumes/emptydir-pod.yaml
volumes:
  - name: app-storage
    emptyDir: {}          # emptyDir: { medium: Memory } would use a tmpfs instead of disk
```

**Experiment** ([screenshot 01](../screenshots/01-emptydir-volume.png)):

```bash
kubectl apply -f 01-volumes/emptydir-pod.yaml
kubectl exec emptydir-demo -- sh -c 'echo "Hello Kubernetes" > /data/message.txt'
kubectl exec emptydir-demo -- nginx -s quit            # container exits, kubelet restarts it
kubectl exec emptydir-demo -- cat /data/message.txt    # still there: same Pod
kubectl delete pod emptydir-demo && kubectl apply -f 01-volumes/emptydir-pod.yaml
kubectl exec emptydir-demo -- cat /data/message.txt    # No such file or directory
```

- After `nginx -s quit` the container restarted (`RESTARTS 1`) but the file was still there. An emptyDir
  belongs to the **Pod**, not the container.
- After deleting and recreating the Pod, the file was gone. It was a new Pod with a new IP and a new, empty directory.

![emptyDir survives a container restart but not a Pod delete](../screenshots/01-emptydir-volume.png)

---

## 2. `hostPath`

Mounts a file or directory **from the node** into the Pod.

```yaml
# 01-volumes/hostpath-pod.yaml
volumes:
  - name: host-storage
    hostPath:
      path: /tmp/hostpath-data
      type: DirectoryOrCreate   # create the directory on the node if it is missing
```

**Experiment** ([screenshot 02](../screenshots/02-hostpath-volume.png)): I wrote a file from the Pod, read it
directly on the node with `minikube ssh`, deleted the Pod, and the recreated Pod could still read it.

When to use it, and when not to:

- Data is tied to **one node**. On a multi-node cluster a rescheduled Pod can land on another node and see
  an empty directory.
- It is a security risk because it gives the Pod access to the host filesystem. Many clusters block it with
  Pod Security Standards (`baseline` and `restricted` do not allow it).
- Good for: local labs, and node agents that really need host files (log collectors reading
  `/var/log`, monitoring agents). Not for application data.

![hostPath data lives on the node and outlives the Pod](../screenshots/02-hostpath-volume.png)

---

## 3. PersistentVolume (PV)

A PV is a piece of storage **in the cluster**, with its own lifecycle that does not depend on any Pod. An
admin creates it, or a provisioner creates it automatically (see section 6). Important fields:

```yaml
# 02-persistent-storage/pv.yaml
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /tmp/student-data      # the backend; in the cloud this would be EBS, EFS, NFS, ...
```

| Access mode | Short | Meaning |
|-------------|-------|---------|
| ReadWriteOnce | RWO | read-write by Pods on **one node** |
| ReadOnlyMany | ROX | read-only by many nodes |
| ReadWriteMany | RWX | read-write by many nodes (needs NFS/EFS/CephFS, ...) |
| ReadWriteOncePod | RWOP | read-write by **one Pod** only |

| Reclaim policy | What happens to the PV when its PVC is deleted |
|----------------|-----------------------------------------------|
| `Retain` | PV becomes `Released`; the data stays and an admin must clean it up |
| `Delete` | PV and the underlying storage are deleted (default for dynamically provisioned PVs) |

PV status lifecycle: `Available` → `Bound` → `Released` (→ deleted or manually reclaimed).

## 4. PersistentVolumeClaim (PVC)

A PVC is a Pod's **request** for storage: "I need 500Mi, RWO". Kubernetes binds it to a PV that satisfies
the request. The Pod only refers to the claim, never to the PV:

```yaml
# 02-persistent-storage/pvc.yaml              # 02-persistent-storage/pod.yaml
spec:                                          volumes:
  accessModes: [ReadWriteOnce]                   - name: persistent-storage
  resources:                                       persistentVolumeClaim:
    requests:                                        claimName: student-pvc
      storage: 500Mi
```

### Gotcha I hit: the default StorageClass grabbed my PVC

The lesson expects `student-pvc` to bind to `student-pv`. On minikube it did **not**
([screenshot 03](../screenshots/03-pv-pvc-default-storageclass.png)):

- `pvc.yaml` has no `storageClassName`, so the **DefaultStorageClass admission plugin** set it to
  `standard` (minikube's default).
- `student-pv` has no class (`""`). A PVC only binds to a PV of the **same** class, so the PV was ignored,
  and the `standard` provisioner created a brand-new 500Mi PV (`pvc-8e2b...`) instead. `student-pv` stayed `Available`.

![PVC without storageClassName gets the default class and a dynamic PV](../screenshots/03-pv-pvc-default-storageclass.png)

**Fix:** set `storageClassName: ""` on the claim. That means "no class", so it only matches PVs that have
no class either ([screenshot 04](../screenshots/04-pv-pvc-static-binding.png)). Without editing the file:

```bash
kubectl create -f pvc.yaml --dry-run=client -o json | jq '.spec.storageClassName = ""' | kubectl apply -f -
```

The claim bound to `student-pv` and shows **1Gi**, not 500Mi. A claim gets the whole PV it binds to, even
when it asked for less.

![PVC with storageClassName "" binds to the static student-pv](../screenshots/04-pv-pvc-static-binding.png)

**Persistence test** ([screenshot 05](../screenshots/05-pv-data-survives-pod.png)): I wrote
`/data/message.txt` in `storage-demo`, deleted the Pod, recreated it, and the file was still there. It is
also visible on the node in `/tmp/student-data`. `kubectl describe pvc` shows `Used By: storage-demo`.

![Data written through the PVC survives Pod deletion](../screenshots/05-pv-data-survives-pod.png)

---

## 5. StorageClass

A StorageClass describes a *kind* of storage (fast SSD, cheap HDD, NFS, ...) and **which provisioner**
creates volumes for it. minikube ships one:

```text
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate           false
```

| Field | Meaning |
|-------|---------|
| `provisioner` | the driver that creates the volume (`ebs.csi.aws.com`, `k8s.io/minikube-hostpath`, ...) |
| `reclaimPolicy` | policy given to the PVs it creates (`Delete` by default) |
| `volumeBindingMode` | `Immediate` = provision as soon as the PVC exists; `WaitForFirstConsumer` = wait until a Pod uses it, so the volume is created in the Pod's zone |
| `allowVolumeExpansion` | whether a PVC can be resized later |
| `(default)` annotation | `storageclass.kubernetes.io/is-default-class: "true"`: used for PVCs without a class |

The minikube provisioner runs as the `storage-provisioner` Pod in `kube-system`
([screenshot 06](../screenshots/06-storageclass.png)).

![kubectl get/describe storageclass standard](../screenshots/06-storageclass.png)

## 6. Dynamic provisioning

With a StorageClass, nobody creates PVs by hand: **PVC → StorageClass → provisioner → new PV**.

```yaml
# 03-storageclass/pvc.yaml
spec:
  storageClassName: standard
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 500Mi } }
```

What I saw ([screenshot 07](../screenshots/07-dynamic-provisioning.png)):

1. `dynamic-pvc` was `Bound` within seconds to `pvc-1d7c5a92-...` (exactly 500Mi, class `standard`, policy `Delete`).
2. The PVC events show the provisioner at work: `ExternalProvisioning` → `Provisioning` → `ProvisioningSucceeded`.
3. On the node the volume is just a directory: `/tmp/hostpath-provisioner/default/dynamic-pvc`.
4. Reclaim policy in action: deleting `dynamic-pvc` removed its PV completely (`Delete`), while deleting
   `student-pvc` left `student-pv` in `Released` with its data intact (`Retain`).

![Dynamic provisioning and Delete vs Retain](../screenshots/07-dynamic-provisioning.png)

---

## Summary

```text
emptyDir   : scratch space, lives and dies with the Pod
hostPath   : a node directory, tied to one node, avoid for app data
PV         : a piece of cluster storage (admin-created or provisioned)
PVC        : a Pod's request for storage; binds to one PV of the same StorageClass
StorageClass + provisioner : create PVs on demand  ->  dynamic provisioning
```

Rules of thumb:

- Applications should only ever use **PVCs**. Let the StorageClass decide where the data physically lives.
- Check `kubectl get pvc`. A claim stuck in `Pending` means no matching PV and no working provisioner
  (`kubectl describe pvc` shows why).
- Use `Retain` for data you cannot lose; `Delete` cleans up automatically.
- Mixing static PVs with a default StorageClass needs `storageClassName: ""` (or the same class name on both sides).

References: [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/) ·
[Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
[Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) ·
[Dynamic Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)
