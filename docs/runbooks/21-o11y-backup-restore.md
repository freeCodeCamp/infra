# 21 — o11y backup and restore (ops-o11y-vultr)

**Audience:** operator. **Trigger:** the alert `O11yBackupStale` fires, the metrics or logs disks are lost, or you practise a restore.

Run every command from the repo root.

## What runs

CronJobs in the namespace `o11y` copy data to the R2 bucket `ops-o11y-backups` each night:

| CronJob                   | Time (UTC) | Source                   | Destination                 |
| ------------------------- | ---------- | ------------------------ | --------------------------- |
| `vmbackup-vmstorage-vm-0` | 01:00      | disk of `vmstorage-vm-0` | `vmstorage/vmstorage-vm-0/` |
| `vmbackup-vmstorage-vm-1` | 01:30      | disk of `vmstorage-vm-1` | `vmstorage/vmstorage-vm-1/` |
| `vmbackup-vmstorage-vm-2` | 02:00      | disk of `vmstorage-vm-2` | `vmstorage/vmstorage-vm-2/` |
| `vlogs-backup`            | 02:30      | disk of `vlogs-a`        | `vlogs/<YYYYMMDD>/`         |

The bucket holds one copy of the metrics, the state of the last night. The logs copy holds each daily partition until it is 15 days old. The Secret `o11y-r2-backups` comes from the 1Password item `o11y-r2-backups`.

To start a backup now:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y create job --from=cronjob/vlogs-backup vlogs-backup-manual
```

## Practise a restore

The practice uses new disks and new pods. It does not touch the running data. The pods do not join the cluster. Each o11y VM must have free disk for one copy of the data.

1. Start the pods, and record the time:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y apply -f k3s/ops-o11y-vultr/tools/restore-drill.yaml
   ```

1. Wait for each restore to complete, and record the time:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y wait --for=condition=Ready --timeout=4h pod/restore-drill-metrics pod/restore-drill-logs
   ```

1. Read the row counts. Each count must be more than 0. The metrics count must be near the count of `vmstorage-vm-0` at the time of its backup:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get --raw /api/v1/namespaces/o11y/pods/restore-drill-metrics:8482/proxy/metrics | grep '^vm_rows{'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get --raw /api/v1/namespaces/o11y/pods/restore-drill-logs:9428/proxy/metrics | grep '^vl_storage_rows'
   ```

1. Remove the pods and their disks:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y delete -f k3s/ops-o11y-vultr/tools/restore-drill.yaml
   ```

## Restore after a loss

Do not restore after the loss of one `vmstorage` disk. Each sample is on 2 of the 3 VMs, so the data stays available. Restore only if 2 or more disks are lost. Restore `vlogs-a` or `vlogs-b` only if its disk is lost.

If a VM is gone, delete its PersistentVolumeClaim and let the workload create a new, empty disk before you start. The restore fills that disk.

1. Stop the Argo CD sync, so that it does not undo the next steps:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application victoria-metrics --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application victoria-logs --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```

1. Stop the workload. For metrics:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y patch vmcluster vm --type merge -p '{"spec":{"paused":true}}'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y scale statefulset vmstorage-vm --replicas=0
   ```

   For logs, do the same for one VLSingle. This example is `vlogs-a`:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y patch vlsingle vlogs-a --type merge -p '{"spec":{"paused":true}}'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y scale deployment vlsingle-vlogs-a --replicas=0
   ```

1. Run the restore. Use the label for the disks that you restore: `restore=vmstorage` (all 3), or `restore=vlogs-a`, or `restore=vlogs-b`:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y apply -l restore=vmstorage -f k3s/ops-o11y-vultr/tools/restore.yaml
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y wait --for=condition=Complete --timeout=4h -l restore=vmstorage job
   ```

1. Start the workload again. Set `paused` to `false` on the same resource, and set the replicas back: `3` for `vmstorage-vm`, `1` for a VLSingle.
1. Delete the restore Jobs:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y delete job -l restore=vmstorage
   ```

1. Start the Argo CD sync again. The root application restores the sync of the other applications:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```

## Failure modes

| Symptom                                          | Cause                                       | Fix                                                              |
| ------------------------------------------------ | ------------------------------------------- | ---------------------------------------------------------------- |
| The pod is in `CreateContainerConfigError`       | The Secret `o11y-r2-backups` does not exist | Examine `kubectl -n o11y get externalsecret o11y-r2-backups`     |
| The log shows `403` or `AccessDenied`            | The R2 key cannot use the bucket            | Check the key scope in the Cloudflare dashboard                  |
| `vlogs-backup` prints `no partitions to back up` | `vlogs-a` has no data                       | Examine the log shipper ([19-o11y-alerts.md](19-o11y-alerts.md)) |
