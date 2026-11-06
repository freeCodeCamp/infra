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

1. Wait for each restore to complete, and record the time. This wait does not end if a restore fails, so examine the pods with `kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pod restore-drill-metrics restore-drill-logs`:

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

Restore only the lost disks. A restore rolls a disk back to its last backup, so a healthy disk loses newer samples.

> **Danger.** A backup makes the bucket match its disk. If a backup runs on a new, empty disk, it deletes the only copy of that disk. Stop the backups (step 2) before you delete a disk.

A disk is on its VM, so a lost disk usually means a lost VM. If a VM is lost, do steps 1 and 2 before it joins the cluster again, and delete each Pending backup Job of that disk. Otherwise a backup can run on the new, empty disk.

Each sample is on 2 of the 3 `vmstorage` VMs, so the metrics stay available after the loss of one disk. You can choose the time of that restore. Do steps 1 to 3 now, and keep the backup of that disk stopped until you restore it. `O11yBackupStale` fires as a reminder. During the delay:

- The new disk takes samples that the restore can remove. Those samples have one copy.
- You can start the Argo CD sync again after step 3, because it does not undo the stopped backup. Do step 1 again before the restore.

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

1. Stop the backup of each lost disk. This example is `vmstorage-vm-0`. For a logs disk, stop `vlogs-backup`:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y patch cronjob vmbackup-vmstorage-vm-0 --type merge -p '{"spec":{"suspend":true}}'
   ```

1. Replace each lost disk. A finished Job can hold the disk, so first read and delete the Jobs of that CronJob. Then delete the PersistentVolumeClaim and the pod, and wait for the new claim. For `vlogs-a`, the claim is `vlsingle-vlogs-a`, and the pod name starts with `vlsingle-vlogs-a-`.

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get jobs -o name | grep vmbackup-vmstorage-vm-0
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y delete <job name from the command before>
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y delete pvc vmstorage-db-vmstorage-vm-0 --wait=false
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y delete pod vmstorage-vm-0
   ```

   If the VM is dead, this delete does not end. Stop it, and add `--force --grace-period=0`.

   Wait for the new claim. The command ends only when a claim is `Bound` and is not being deleted. For a VLSingle, this can take about 1 minute. Do not go on to step 4 before it ends:

   ```sh
   until [ "$(kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pvc vmstorage-db-vmstorage-vm-0 -o jsonpath='{.status.phase}/{.metadata.deletionTimestamp}')" = "Bound/" ]; do sleep 5; done
   ```

> **Outage.** For metrics, step 4 stops all 3 `vmstorage` pods. All metrics, metric alerts and queries stop until step 6, and this can take hours. Tell the Google Chat space first. Sentry reports a missed Watchdog check-in. Samples that `vmagent` cannot hold on its disk during this time are lost.

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

1. Run the restore once for each lost disk. The label is `restore-disk=<disk>`, where `<disk>` is `vmstorage-vm-0`, `vmstorage-vm-1`, `vmstorage-vm-2`, `vlogs-a` or `vlogs-b`:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y apply -l restore-disk=vmstorage-vm-0 -f k3s/ops-o11y-vultr/tools/restore.yaml
   ```

   This wait does not end if the Job fails, so examine the Job in a second terminal:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y wait --for=condition=Complete --timeout=4h -l restore-disk=vmstorage-vm-0 job
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get job -l restore-disk=vmstorage-vm-0 -w
   ```

1. Start the workload again. Set `paused` to `false` on the same resource, and set the replicas back: `3` for `vmstorage-vm`, `1` for a VLSingle.
1. Delete the restore Jobs:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y delete job -l restore-disk
   ```

1. Read the row counts, and make sure that the data is back. For a VLSingle, read its pod name with `kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods`.

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get --raw /api/v1/namespaces/o11y/pods/vmstorage-vm-0:8482/proxy/metrics | grep '^vm_rows{'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get --raw /api/v1/namespaces/o11y/pods/<VLSingle pod>:9428/proxy/metrics | grep '^vl_storage_rows'
   ```

1. When the data is back, start each backup again. Argo CD does not undo the stop:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y patch cronjob vmbackup-vmstorage-vm-0 --type merge -p '{"spec":{"suspend":false}}'
   ```

1. Start the Argo CD sync again. The root application restores the sync of the other applications:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```

## Failure modes

| Symptom                                              | Cause                                       | Fix                                                                                                                              |
| ---------------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| The pod is in `CreateContainerConfigError`           | The Secret `o11y-r2-backups` does not exist | Examine `kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get externalsecret o11y-r2-backups`                    |
| `vmrestore` stops because the backup is not complete | The last backup failed part way             | Run the next backup first. If the disk is lost, add `-skipBackupCompleteCheck` to the restore Job; the restore can be incomplete |
| The log shows `403` or `AccessDenied`                | The R2 key cannot use the bucket            | Check the key scope in the Cloudflare dashboard                                                                                  |
| `vlogs-backup` prints `no partitions to back up`     | `vlogs-a` has no data                       | Examine the log shipper ([19-o11y-alerts.md](19-o11y-alerts.md))                                                                 |
