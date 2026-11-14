# 21 — o11y backup and restore (ops-o11y-vultr)

**Audience:** operator. **Trigger:** the alert `O11yBackupStale` or `O11yBackupFailed` fires, the metrics or logs disks are lost, the K3s control plane is lost, or you practise a restore.

Run every command from the repo root.

## What runs

CronJobs in the namespace `o11y` copy data to the R2 bucket `ops-o11y-backups` each night:

| CronJob                   | Time (UTC)                 | Source                   | Destination                                     |
| ------------------------- | -------------------------- | ------------------------ | ----------------------------------------------- |
| `vmbackup-vmstorage-vm-0` | 07:00, and the Sunday copy | disk of `vmstorage-vm-0` | `vmstorage/vmstorage-vm-0/`                     |
| `vmbackup-vmstorage-vm-1` | 07:15, and the Sunday copy | disk of `vmstorage-vm-1` | `vmstorage/vmstorage-vm-1/`                     |
| `vmbackup-vmstorage-vm-2` | 07:30, and the Sunday copy | disk of `vmstorage-vm-2` | `vmstorage/vmstorage-vm-2/`                     |
| the same 3 CronJobs       | Sunday                     | same disks               | `vmstorage-weekly/<YYYY>-W<WW>/vmstorage-vm-N/` |
| `vlogs-backup`            | 07:45                      | disk of `vlogs-a`        | `vlogs/<YYYYMMDD>/`                             |

The backups run after the housekeeping window (00:00-06:00 UTC on Wednesday and Saturday), so a node reboot does not stop them.

The bucket holds the metrics of the last night in `vmstorage/`. On Sunday each CronJob also makes a dated copy in `vmstorage-weekly/`. An R2 lifecycle rule must remove dated copies after 35 days: vmbackup does not prune. The operator makes this rule in Cloudflare on the bucket `ops-o11y-backups`, with the prefix `vmstorage-weekly/` and an expiry of 35 days. Without the rule, the dated copies stay. Do not put the rule on `vmstorage/`. The logs copy holds each daily partition until it is 15 days old. The Secret `o11y-r2-backups` comes from the 1Password item `o11y-r2-backups`.

The 3 log stores `vlogs-a`, `vlogs-b` and `vlogs-c` run one on each o11y VM. `vlagent` writes each log to all 3, so each store is a full copy. Only `vlogs-a` is backed up. A restore of `vlogs-b` or `vlogs-c` uses this backup of `vlogs-a`.

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

To restore an older copy, set `-src` in the restore Job to `s3://ops-o11y-backups/vmstorage-weekly/<YYYY>-W<WW>/vmstorage-vm-N`. Use it if the last nightly copy is empty or corrupt.

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

1. Run the restore once for each lost disk. The label is `restore-disk=<disk>`, where `<disk>` is `vmstorage-vm-0`, `vmstorage-vm-1`, `vmstorage-vm-2`, `vlogs-a`, `vlogs-b` or `vlogs-c`:

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

1. Start the workload again. Set `paused` to `false` on the same resource. For `vmstorage-vm`, also set the replicas back to `3`. For a VLSingle, the VictoriaMetrics operator sets the replicas back to `1`.
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

## Seed a new log store

Use this when `vlogs-c` starts for the first time. It copies the history of `vlogs-a` from R2 to the new store. It uses the same restore Job as a restore after a loss. The nightly backup is not stopped: it reads `vlogs-a` only, and this procedure writes to `vlogs-c` only.

`vlagent` holds the logs for `vlogs-c` on its disk while `vlogs-c` is down, and sends them when it is back. The history of `vlogs-c` has a gap from the time of the backup to the time that `vlagent` began to hold logs for it. Logs that arrive in this gap are in `vlogs-a` and `vlogs-b`. `vmauth` reads `vlogs-a` first, so the gap shows only when `vlogs-a` and `vlogs-b` are down. To make the gap short, do step 1.

1. Before you merge the change that adds `vlogs-c`, start a backup, and wait for it to complete:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y create job --from=cronjob/vlogs-backup vlogs-backup-manual
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y wait --for=condition=Complete --timeout=3h job/vlogs-backup-manual
   ```

   Make sure that `vlogs-a` and `vlogs-b` are `Running` before you merge. A store that restarts during the merge can let `vlogs-c` take its VM:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l 'app.kubernetes.io/instance in (vlogs-a,vlogs-b)' -o wide
   ```

1. Merge the change. Argo CD creates `vlogs-c`. Wait until the pod is `Running` on `ops-vm-o11y-2`. The first start makes the disk on that VM:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l app.kubernetes.io/instance=vlogs-c -o wide
   ```

1. Stop the Argo CD sync, so that it does not undo the next steps:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application victoria-logs --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```

1. Stop `vlogs-c`:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y patch vlsingle vlogs-c --type merge -p '{"spec":{"paused":true}}'
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y scale deployment vlsingle-vlogs-c --replicas=0
   ```

   Wait until the pod is gone, so that it does not write to the disk during the restore:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y wait --for=delete pod -l app.kubernetes.io/instance=vlogs-c --timeout=5m
   ```

1. Run the restore. The restore makes the partitions of `vlogs-c` the same as the backup. It removes logs that `vlogs-c` took before step 4 and that are not in the backup. This wait does not end if the Job fails, so examine the Job in a second terminal:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y apply -l restore-disk=vlogs-c -f k3s/ops-o11y-vultr/tools/restore.yaml
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y wait --for=condition=Complete --timeout=4h -l restore-disk=vlogs-c job
   ```

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get job -l restore-disk=vlogs-c -w
   ```

1. Start `vlogs-c` again. Set `paused` to `false`. The VictoriaMetrics operator then sets the replicas back to `1`:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y patch vlsingle vlogs-c --type merge -p '{"spec":{"paused":false}}'
   ```

1. Delete the restore Job:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y delete job -l restore-disk=vlogs-c
   ```

1. Read the row count of `vlogs-c`, and compare it with `vlogs-a`. The count of `vlogs-c` must be more than 0 and near the count of `vlogs-a`. Read the pod names with `kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -o wide`:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get --raw /api/v1/namespaces/o11y/pods/<VLSingle pod>:9428/proxy/metrics | grep '^vl_storage_rows'
   ```

1. Start the Argo CD sync again. The root application restores the sync of the other applications:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```

## Restore etcd

Use this only if the K3s control plane is lost or its data is bad. K3s keeps a snapshot of etcd every 6 hours in the R2 bucket `ops-o11y-etcd` (settings: `ansible/inventory/group_vars/ops_o11y_vultr.yml`). A restore rolls the cluster state back to the time of the snapshot. Source: [K3s etcd-snapshot](https://docs.k3s.io/cli/etcd-snapshot).

> **Not drilled.** Nobody has run this procedure on this cluster. The steps come from the K3s documentation. Do a drill before you need it.

Prerequisites:

- The server token from the first server (`/var/lib/rancher/k3s/server/token`). The cluster uses secrets encryption, so K3s does not start with a different token.
- The R2 endpoint, key and secret from the 1Password item `R2-User-Token-Infra-O11y-etcd`. You need them to list the bucket, and for a new host.

1. Find the name of the snapshot to restore. Pick the newest good one. Its name starts `etcd-snapshot-<node>-`. If the API still runs, read the names from the cluster, or from a server:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get etcdsnapshotfile
   ```

   ```sh
   sudo k3s etcd-snapshot ls
   ```

   If the API is down, `k3s etcd-snapshot ls` does not work. Read the object list of the R2 bucket `ops-o11y-etcd` in the Cloudflare dashboard, or list the bucket with an S3 client and the etcd key.

1. Stop K3s on all 3 servers:

   ```sh
   sudo systemctl stop k3s
   ```

1. On the first server (`ops-vm-o11y-1`), reset the cluster from the snapshot. Give only the snapshot file name, not a path. Replace the value in `<>`:

   ```sh
   sudo k3s server --cluster-reset --cluster-reset-restore-path=<snapshot-file-name>
   ```

   K3s reads the S3 settings from its config, which includes the files in `/etc/rancher/k3s/config.yaml.d/`.

   For a new host that does not have the file `/etc/rancher/k3s/config.yaml.d/etcd-s3.yaml`, give the S3 settings as flags. First make sure that your K3s version accepts them with `sudo k3s server --help | grep etcd-s3`. Replace the values in `<>`:

   ```sh
   sudo k3s server --cluster-reset --cluster-reset-restore-path=<snapshot-file-name> --etcd-s3 --etcd-s3-endpoint=<endpoint> --etcd-s3-bucket=ops-o11y-etcd --etcd-s3-region=auto --etcd-s3-access-key=<key> --etcd-s3-secret-key=<secret>
   ```

   Wait for this line: `Managed etcd cluster membership has been reset, restart without --cluster-reset flag now.`

1. Start K3s on the first server:

   ```sh
   sudo systemctl start k3s
   ```

1. On each other server (`ops-vm-o11y-2`, `ops-vm-o11y-3`), move the etcd data away, then start K3s. Do one server at a time:

   ```sh
   sudo mv /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db.bak
   sudo systemctl start k3s
   ```

1. Make sure that all 3 nodes are Ready, and that Argo CD shows its 8 applications Synced:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get nodes
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd get applications
   ```

To restore on a new host, add `--token=<token-of-the-old-first-server>` to the command in step 3.

## Failure modes

| Symptom                                              | Cause                                       | Fix                                                                                                                              |
| ---------------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| The pod is in `CreateContainerConfigError`           | The Secret `o11y-r2-backups` does not exist | Examine `kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get externalsecret o11y-r2-backups`                    |
| `vmrestore` stops because the backup is not complete | The last backup failed part way             | Run the next backup first. If the disk is lost, add `-skipBackupCompleteCheck` to the restore Job; the restore can be incomplete |
| The log shows `403` or `AccessDenied`                | The R2 key cannot use the bucket            | Check the key scope in the Cloudflare dashboard                                                                                  |
| `vlogs-backup` prints `no partitions to back up`     | `vlogs-a` has no data                       | Examine the log shipper ([19-o11y-alerts.md](19-o11y-alerts.md))                                                                 |
| The Sunday copy fails with a copy error              | R2 refused the server-side copy             | Remove `-origin` from the second vmbackup line. The copy is then a full upload.                                                  |
| K3s fails to start after the restore                 | The token differs from the snapshot token   | Start with `--token=<old token>`                                                                                                 |
