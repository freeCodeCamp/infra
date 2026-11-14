# 19 — o11y alerts (ops-o11y-vultr)

**Audience:** operator. **Trigger:** an alert from the `ops-o11y-vultr` cluster arrives in Google Chat, or the Sentry Cron Monitor of the Watchdog reports a missed check-in.

Each alert has one section here. The section name is the alert name. The alert links to its section in the `runbook_url` annotation.

calert sends one Chat card for each Alertmanager group (one alert name and job), with up to 10 alerts in it. Later changes to the group go to the same Chat thread. Google Chat takes 1 message per second for each space, so one card for each group keeps a burst of alerts from being dropped. calert uses its built-in group template. calert reads its config only when it starts. After a change to `calert-config` alone, wait until Argo CD shows `calert-config` synced, then restart calert:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y rollout restart deploy/calert
```

Run every command from the repo root unless the step says otherwise.

## Preconditions

- Your shell is on the tailnet.
- `k3s/ops-o11y-vultr/.kubeconfig.yaml` exists.

## Reach a host that is not on the tailnet

The `pxy`, `api`, `soc` and `nws` VMs are not on the tailnet, so `ssh freecodecamp@<instance>` does not find them. Connect through the Swarm manager to the VPC address of the VM. The steps in each alert section below then work with this `ssh` command.

1. Get the VPC address of the VM. Use the `instance` label of the alert. From `ansible/`, with `VULTR_API_KEY` set:

   ```sh
   ansible-inventory -i inventory/vultr.yml --host <instance> | jq -r .vultr_internal_ip
   ```

   For an `api`, `soc` or `nws` VM, the manager also has the address, with no API key:

   ```sh
   ssh freecodecamp@ops-vm-swarm-mgr-1 docker node inspect -f '{{.Status.Addr}}' <instance>
   ```

1. Connect through the manager:

   ```sh
   ssh -J freecodecamp@ops-vm-swarm-mgr-1 freecodecamp@<vpc address> uptime
   ```

   The output starts with the VM uptime. If the manager does not answer, see [runbook 18](18-swarm-manager-rebuild.md).

## See the alerts that fire

Grafana evaluates no rules and sends no notification. All alerts come from vmalert through Alertmanager. The **Alerting** menu of Grafana shows them:

- **Active notifications**, Alertmanager `Alertmanager`: the alerts that Alertmanager holds now, in groups, with the receiver of each group.
- **Silences**: add or expire a silence in Alertmanager.
- **Notification configuration**: the routes and receivers of Alertmanager, read-only. To change them, change `alertmanager.config` in `k3s/ops-o11y-vultr/apps/victoria-metrics/charts/victoria-metrics-k8s-stack/values.yaml`. Argo CD applies the change.
- **Alert rules**, source `VictoriaMetrics`: the metric rules of `vmalert-vm` and their state, read through vmselect. When `vmalert-vm` is down, the source shows an error. The log rules of `vmalert-vlogs` are not in this list.

Do not add a Grafana-managed rule. Its only contact point, `empty`, sends nothing, and Grafana loses the rule when its pod starts again.

To see the log rules, or the metric rules when Grafana is down, open the vmalert UI:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y port-forward svc/vmalert-vm 8880:8080
```

Then open `http://127.0.0.1:8880/vmalert/alerts`. For the log rules, use `svc/vmalert-vlogs` in place of `svc/vmalert-vm`.

To read logs, use **Explore** in Grafana. The datasource `VictoriaLogs` goes through vmauth. The datasources `VictoriaLogs vlogs-a`, `VictoriaLogs vlogs-b` and `VictoriaLogs vlogs-c` each read one store directly. Use them when vmauth is down, or to compare the stores. The VictoriaLogs UI is at `http://<o11y node>:30427/select/vmui`, through vmauth. Log in as `ops`.

To see the sync state, resources, events and pod logs of each Argo CD Application, open Argo CD at `https://argocd-o11y.<tailnet>.ts.net`, or at `http://ops-vm-o11y-1:30081`. The three o11y nodes serve the HTTPS name as the Tailscale Service `svc:argocd-o11y` (`play-vultr--o11y-tailnet-services.yml`). Log in as `admin` with the password from 1Password. Until someone changes the first password, read it from the cluster:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

To see traffic, errors, probes and host health, open Grafana at `https://<grafana-host>`. This is the MagicDNS name of the Tailscale Service, shown in the Tailscale admin console under **Services**. The three o11y nodes serve it as the Tailscale Service `svc:grafana` (`play-vultr--o11y-tailnet-services.yml`). Grafana has no NodePort, and the browser sends its login cookie only over HTTPS. Log in with the 1Password item `o11y-grafana-admin` (vault `Infra-IaC-ESO`, fields `username` and `password`). Grafana does not start without this item. The home page is the dashboard **Traffic and health**. The folder **freeCodeCamp** also has **Fleet capacity and stability**. The folders **VictoriaMetrics** and **Hosts** have the upstream dashboards. These are files in `k3s/ops-o11y-vultr/cluster/grafana/dashboards/`, so Grafana starts without GitHub. They come from `VictoriaMetrics/VictoriaMetrics` at `29c43cd2`, `VictoriaMetrics/VictoriaLogs` at `915d9190` and `rfmoz/grafana-dashboards` at `b07d8a90`, with the panels removed whose metrics we do not collect.

To silence an alert during planned work, open **Alerting > Silences** in Grafana, select the Alertmanager `Alertmanager`, and add a silence with an end time. If Grafana is down, open the Alertmanager UI:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y port-forward svc/vmalertmanager-vm 9093:9093
```

Then open `http://127.0.0.1:9093/#/silences` and add a silence with an end time.

## Test the alert path

This test proves that an alert goes through Alertmanager and calert to Google Chat. It does not prove that the rule expression is correct. The test alerts have the label `drill="true"` and a name that starts with `DRILL-`. Alertmanager sends them to the receiver `google_chat_drill`, and calert posts them to the drill space, not to the alert space. The webhook of the drill space is in the 1Password item `o11y-google-chat-drill-webhook` in the vault `Infra-IaC-ESO`. The test does not use the webhook of the alert space.

1. Read the list of alerts that the test sends:

   ```sh
   k3s/ops-o11y-vultr/tools/alert-drill.sh --dry-run
   ```

1. Send the alerts:

   ```sh
   k3s/ops-o11y-vultr/tools/alert-drill.sh --send
   ```

1. In the drill space, make sure that one message with `DRILL-` in its title comes for each alert in the list, in about 1 minute. About 16 minutes after you send, each alert gets a message or a thread reply with a title that ends in `Resolved`. Do not send again during this time: Alertmanager merges the alerts and posts no new messages.
1. Test the Watchdog. Add a silence with the matcher `alertname="Watchdog"` and an end time of 1 hour. The CronJob stops its check-ins, and Sentry reports a missed check-in. While the silence is on, each run of the CronJob fails with `Watchdog is not active; no check-in`, and the last 3 failed Jobs stay in the `o11y` namespace. This is correct.
1. When Sentry reports it, expire the silence. Make sure that the Sentry monitor becomes OK at the next check-in.

The test sends the metric alerts and the log alerts (`NginxHigh5xxRate`, `NginxUpstreamErrors`). To send the alerts of one rule file only, give the file after `--dry-run` or `--send`. This test does not use `vmalert-vlogs`, so it does not prove the path from `vmalert-vlogs` to Alertmanager.

## HostDown

A host does not send metrics for about 5 minutes. The alert does not cover the NGINX VMs; see [NginxVmDown](#nginxvmdown).

- The host has sent metrics in the last day, but not in the last 2 minutes. Fluent Bit on the host reads the node exporter and sends the metrics. If Fluent Bit stops, this alert fires.
- A destroyed or rebuilt Vultr VM alerts until it sends again or until it has been gone for 1 day. Silence the alert for that `instance` before you destroy the VM.

1. Connect to the host. Use the `instance` label of the alert. For a `pxy`, `api`, `soc` or `nws` VM, use `ssh -J` as in [Reach a host that is not on the tailnet](#reach-a-host-that-is-not-on-the-tailnet), here and in each step below:

   ```sh
   ssh freecodecamp@<instance> uptime
   ```

1. If `ssh` fails, open the cloud provider console of the host and restart it.
1. If `ssh` works, examine the node exporter:

   ```sh
   ssh freecodecamp@<instance> sudo systemctl status node_exporter
   ```

1. Start the node exporter again if it stopped:

   ```sh
   ssh freecodecamp@<instance> sudo systemctl restart node_exporter
   ```

1. On a Vultr host, examine Fluent Bit too, and start it again if it stopped:

   ```sh
   ssh freecodecamp@<instance> sudo systemctl status fluent-bit
   ssh freecodecamp@<instance> sudo systemctl restart fluent-bit
   ```

1. If Fluent Bit runs, look for a refused sender token. A `401` also stops the logs of the host. Do the steps in [Sender token](../infra-guides/ansible.md#sender-token):

   ```sh
   ssh freecodecamp@<instance> 'sudo journalctl -u fluent-bit --since -30min --no-pager | grep -c "HTTP status=401"'
   ```

## NginxVmDown

An NGINX VM does not send metrics, or `nginx.service` is not active, for about 4 minutes. The rule for a missing host is the same as in [HostDown](#hostdown).

1. Examine NGINX on the VM. The NGINX VMs are not on the tailnet, so use `ssh -J` as in [Reach a host that is not on the tailnet](#reach-a-host-that-is-not-on-the-tailnet), here and in the next step:

   ```sh
   ssh freecodecamp@<instance> 'sudo nginx -t; sudo systemctl status nginx'
   ```

1. If `nginx -t` prints `test is successful`, start NGINX again:

   ```sh
   ssh freecodecamp@<instance> sudo systemctl restart nginx
   ```

1. If the VM does not answer or NGINX does not start, add the VM to `proxies_down` so that it gets no traffic ([traffic runbook](https://github.com/freeCodeCamp/terraform-cloudflare/blob/main/cf-origin-records/README.md), private repo).
1. Repair or rebuild the VM, then remove it from `proxies_down`.

## DiskSpaceLow

The root file system of a host is more than 85% full for 15 minutes.

1. Find the large directories:

   ```sh
   ssh freecodecamp@<instance> 'sudo du -xh --max-depth=2 / 2>/dev/null | sort -h | tail -15'
   ```

1. If the host runs Docker, remove the unused images:

   ```sh
   ssh freecodecamp@<instance> sudo docker image prune -a -f
   ```

1. If the disk stays above 85%, resize the disk of the VM.

## MemoryHigh

A host uses more than 90% of its memory for 15 minutes.

1. Find the processes that use the most memory:

   ```sh
   ssh freecodecamp@<instance> 'ps -eo pid,rss,comm --sort=-rss | head -10'
   ```

1. Restart the service that leaks memory. If the use is normal for the role, resize the VM.

## VultrMetricsPushDown

No Vultr host has sent metrics for 2 minutes, for 5 minutes. HostDown and NginxVmDown do not fire for the Vultr hosts while this alert fires. Each Vultr host sends its metrics to `fluent_bit_vlagent_host` (the field `vlagent_host` of the 1Password item `ops-vultr-private-network`): to vmauth on port 30427 with the sender token. vmauth sends them on to vmagent. Fluent Bit keeps up to 256M of metrics on disk and sends them when the receiver is back.

1. Make sure that the o11y node at that address is `Ready`, and that vmauth and vmagent run:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get nodes -o wide
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get svc vmauth-o11y vmagent-vm
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l app.kubernetes.io/name=vmagent
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l o11y.freecodecamp.org/component=vmauth
   ```

   The Services must show `8427:30427/TCP` for vmauth and `8429/TCP` for vmagent.

1. Examine the Fluent Bit log on one Vultr host:

   ```sh
   ssh freecodecamp@<host> 'sudo journalctl -u fluent-bit --since -30min --no-pager | grep prometheus_remote_write | tail -20'
   ```

1. If the log shows `HTTP status=401`, vmauth refused the sender token. Fluent Bit keeps the metrics and sends them again. Do the steps in [Sender token](../infra-guides/ansible.md#sender-token).

## TargetDown

A scrape target that is not a host, such as a cluster component or an exporter, is down for 5 minutes. The VictoriaLogs stores have their own alert, [LogStoreDown](#logstoredown).

1. Find the pod of the target. Use the `job` and `instance` labels of the alert:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get pods -A -o wide
   ```

1. Examine the pod events and the log, then delete the pod so that it starts again.

## ProbeFailed

A public URL fails the HTTP probe for 3 minutes. The `instance` label is the URL. The probes are in `k3s/ops-o11y-vultr/cluster/victoria-metrics/vmprobe-public-hostnames.yaml`. They include the News home of each language, such as `https://www.freecodecamp.org/espanol/news/`.

1. Make sure that the failure is real:

   ```sh
   curl -sS -o /dev/null -w '%{http_code}\n' <instance>
   ```

1. If the code is `5xx` or the request fails, examine the NGINX logs and the service behind the hostname. See [NginxHigh5xxRate](#nginxhigh5xxrate).

## ScrapeConfigReloadFailed

The scrape agent cannot load a new scrape configuration for 5 minutes. It continues with the old configuration.

1. Find the error:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs deploy/vmagent-vm -c vmagent --tail=100
   ```

1. Correct the scrape resource or the chart values in git. Argo CD syncs the fix.

## VmalertExecutionErrors

A vmalert pod failed to run one or more of its rules in each 10 minutes, for 5 minutes. The alerts of those rules cannot fire. The `job` label is `vmalert-vm` for the metric rules and `vmalert-vlogs` for the log rules.

1. Find the error. Use the `pod` label of the alert:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs <pod> -c vmalert --tail=100
   ```

1. If the log rules fail, make sure that a VictoriaLogs pod runs. The rules read the service `vlogs-any`, which uses each ready store:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l o11y.freecodecamp.org/component=vlogs
   ```

1. If a rule expression is wrong, correct the rule in git. Argo CD syncs the fix.

## O11yBackupStale

A nightly backup to R2 has not succeeded for 36 hours. The `cronjob` label names it. Examine the last Job, then see [21-o11y-backup-restore.md](21-o11y-backup-restore.md):

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get jobs --sort-by=.metadata.creationTimestamp
```

## O11yBackupFailed

A nightly backup started more than 3 hours ago and has not succeeded. The `cronjob` label names it. Examine the last Job and its log, then see [21-o11y-backup-restore.md](21-o11y-backup-restore.md):

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get jobs --sort-by=.metadata.creationTimestamp
```

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs job/<job-name>
```

The alert clears when a backup succeeds or the next run starts. It fires again 3 hours after each failed run.

## O11yPodRestarting

An o11y container restarted more than 2 times in 30 minutes. The `reason` label shows why it last stopped.

- `OOMKilled`: the container used all of its memory limit. Read its memory use and raise the limit in its manifest, inside the node budget (keep 25% of each node free).
- `Error`: read the log of the stopped container:

  ```sh
  kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs <pod> -c <container> --previous --tail=50
  ```

  On 2026-11-14, `vmalert`, `vmagent` and `vmauth` stopped with `Error` after a kernel update, because containers could not signal themselves. `ansible/tasks/k3s-apparmor-sysctl.yml` fixes this. Make sure that the AppArmor sysctl is `0` on each node:

  ```sh
  kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y exec vmalertmanager-vm-0 -c alertmanager -- cat /proc/sys/kernel/apparmor_restrict_unprivileged_unconfined
  ```

## EtcdSnapshotMissing

The K3s server in the `node` label has not saved an etcd snapshot to R2 in 8 hours. K3s saves one every 6 hours. On the node, list the snapshots and read the K3s log:

```sh
sudo k3s etcd-snapshot ls
```

```sh
sudo journalctl -u k3s --since "12 hours ago" | grep -i snapshot
```

Check the R2 key for the bucket `ops-o11y-etcd` in the Cloudflare dashboard. The key is in the 1Password item `R2-User-Token-Infra-O11y-etcd`. To fix the K3s settings, see `ansible/inventory/group_vars/ops_o11y_vultr.yml`.

## FluentBitDroppedRecords

Fluent Bit on a Vultr host dropped log records or metrics in the last 15 minutes. The `name` label names the output: `http.*` sends logs to the log agent, `prometheus_remote_write.*` sends metrics to vmagent. The rule has no `for`: it fires at the first evaluation that sees a drop, and it stays on for 15 minutes after the last drop. One of two causes applies:

- vmauth or the log agent refused the records with an HTTP 4xx status. Fluent Bit keeps a copy in `/var/lib/fluent-bit/storage/rejected`, up to 256M.
- The buffer of an output became full, and Fluent Bit removed the oldest records. Those records are lost.

1. Find the cause. Use the `instance` label of the alert:

   ```sh
   ssh freecodecamp@<instance> 'sudo journalctl -u fluent-bit --since -30min --no-pager | grep -E "HTTP status=|will not be retried"'
   ```

1. If the output shows `will not be retried`, read the status on the line before it.
1. If the status is `401`, vmauth refused the sender token of the host. Do the steps in [Sender token](../infra-guides/ansible.md#sender-token).
1. For another 4xx status, the log agent refused the records. Examine the log of the log agent:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs -l o11y.freecodecamp.org/component=vlagent --tail=100
   ```

1. If the output does not show `will not be retried`, do the steps in [FluentBitBufferBacklog](#fluentbitbufferbacklog).

## FluentBitBufferBacklog

An output of Fluent Bit on a Vultr host has used half of its buffer for 15 minutes. The output cannot send records to the log agent (`http.*`) or metrics to vmagent (`prometheus_remote_write.*`) as fast as it reads them. Each output has its own limit. A full buffer drops records.

1. Examine the log agent pods:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l o11y.freecodecamp.org/component=vlagent -o wide
   ```

1. If a pod is not ready, examine its events and its log. The buffer empties when the log agent accepts records again.
1. If each pod is ready, find the send error on the host. Use the `instance` label of the alert:

   ```sh
   ssh freecodecamp@<instance> 'sudo journalctl -u fluent-bit --since -30min --no-pager | tail -50'
   ```

1. A connection error shows a fault in the VPC network or the node. An HTTP 5xx status shows a fault in vmauth or the log agent. Examine the vmauth log for the request: `kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs -l o11y.freecodecamp.org/component=vmauth --tail=100`. An HTTP 401 status on metrics shows a wrong sender token; see [Sender token](../infra-guides/ansible.md#sender-token).

## LogStoreDown

A VictoriaLogs store (`vlogs-a`, `vlogs-b` or `vlogs-c`) is not up, or has no scrape target at all, for 5 minutes. The `job` label names it. A lost node removes the target, so the alert also fires when the series is missing. The log agent writes each log to all three stores, and log reads and the log rules use any store that is ready. So one store down loses no data. `VmalertExecutionErrors` may fire once while the pod is still in the service, before the node is marked not ready. A second store down leaves no spare. The agent keeps the data for the down store on its disk, up to 3GiB for each store, and sends it when the store returns. A store that returns is ready at once, but it is behind until the agent sends the backlog, so a log alert may miss events in that time.

1. Find the pod of the store. Use the `job` label of the alert:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l o11y.freecodecamp.org/component=vlogs -o wide
   ```

1. Examine the events and the log of the pod that is not ready:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y describe pod <pod>
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs <pod> --tail=100
   ```

1. If the node or the disk is the cause, see [DiskSpaceLow](#diskspacelow) and [HostDown](#hostdown). If the data is lost, see [21-o11y-backup-restore.md](21-o11y-backup-restore.md).
1. If the store is down for a long time, the buffer of its output can fill. See [VlagentDroppedData](#vlagentdroppeddata).

## LogStoreStale

A VictoriaLogs store is up but has taken no new logs for 10 minutes. The `job` label names it. The store answers queries, so it stays in the service `vlogs-any`. But a query that reaches it returns few or no recent rows, and a log alert that reads it can miss events. The other two stores keep the data.

1. Look for send errors to that store in the log of the log agent:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs -l o11y.freecodecamp.org/component=vlagent --tail=100
   ```

1. Examine the log of the store pod:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs deploy/<job> --tail=100
   ```

1. If the store is full or its disk is read only, see [DiskSpaceLow](#diskspacelow). If the store hangs, delete its pod so that it starts again. The agent sends the backlog when the store accepts data.
1. If all three stores are stale, the log agent or the senders are the cause. See [FluentBitBufferBacklog](#fluentbitbufferbacklog).

## VlagentDroppedData

A log agent pod dropped log data in the last 15 minutes. The rule has no `for`: it fires at the first evaluation that sees a drop, and it stays on for 15 minutes after the last drop. The `pod` label names the agent. Two counters can fire it:

- `vlagent_remotewrite_packets_dropped_total` counts blocks that a store refused with an HTTP 400 or 404 status. The agent does not send them again. The `url` label starts with the number of the output.
- `vm_persistentqueue_blocks_dropped_total` counts blocks that the agent removed because the disk buffer of an output is full (3GiB). The agent removes the oldest data first. The `name` label starts with the number of the output.

The number is the order of `remoteWrite` in `vlagent.yaml`: `1` is `vlogs-a`, `2` is `vlogs-b`, `3` is `vlogs-c`. The other two stores still hold the data that one store lost.

1. Find the reason in the log of the pod. Use the `pod` label of the alert:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs <pod> --tail=100
   ```

1. If the store of the output is down or stale, do the steps in [LogStoreDown](#logstoredown) or [LogStoreStale](#logstorestale). A full buffer means that the store did not take data for a long time.
1. If the store is ready and refuses the data, read the status in the log of the agent and the log of the store.
1. Read the lost period from the other two stores. Through `vlogs-any`, a query can reach the store that lost it, so the result can have a gap.

## ArgoCDAppUnhealthy

An Argo CD Application is not `Healthy`, or not `Synced`, for 15 minutes. The `name` label names the Application. `OutOfSync` means that the cluster is different from git. `Unknown` means that Argo CD cannot compare them. `Synced` but not `Healthy` means that a resource from git does not work. During a restore with [21-o11y-backup-restore.md](21-o11y-backup-restore.md), the sync is stopped, so this alert fires until the restore ends.

1. Find the status of each Application:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd get applications
   ```

1. Read the conditions and the resources that are not healthy or not synced:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n argocd describe application <name>
   ```

1. If a pod is not healthy, examine its events and its log.
1. If the sync fails because a manifest or a chart value is wrong, correct it in git. Argo CD syncs the fix.

## NginxHigh5xxRate

More than 5% of the requests to one `server_name` return a 5xx status for 5 minutes, with at least 100 requests in each 5 minutes.

1. Find the failing upstream in the NGINX error log. Run the query in the VictoriaLogs UI:

   ```text
   _time:15m _stream:{level=~"error|crit|alert|emerg"} upstream
   ```

1. Examine the service behind the upstream. Restart or roll back its last deploy.

## NginxUpstreamErrors

An NGINX VM logs more than 10 upstream errors in 5 minutes for 5 minutes. The alert does not count an error for an IPv6 upstream address. The Vultr VMs have no IPv6 route, so NGINX tries the IPv6 address of a CDN host, fails at once and uses IPv4.

1. Read the errors in the VictoriaLogs UI. Use the `host` label of the alert:

   ```text
   _time:15m _stream:{level=~"error|crit|alert|emerg",host="<host>"} upstream
     !~"upstream: \"https?://\\["
   ```

1. If one upstream fails, examine that service. If all upstreams fail, examine the network of the VM.

## Watchdog

The Watchdog alert always fires. A CronJob sends a Sentry check-in each 5 minutes while the Watchdog is active in Alertmanager. The CronJob also stops its check-ins for 15 minutes after Alertmanager fails to send a notification to Google Chat. If Sentry reports a missed check-in, the alert path is broken.

The Watchdog does not go to Google Chat. Thus the CronJob finds a broken path to Google Chat only when a real alert fails to send. The check-ins start again within about 20 minutes after the last failure. Thus an OK monitor in Sentry does not prove that the path to Google Chat works again.

1. Examine the CronJob runs:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get jobs --sort-by=.metadata.creationTimestamp
   ```

1. Read the log of the last failed Job:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs job/<job-name>
   ```

1. If the log shows `Alertmanager notifications failing; no check-in`, examine the calert pods and their logs, and the Alertmanager logs:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l app.kubernetes.io/name=calert
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs -l app.kubernetes.io/name=calert --tail 50
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs -l app.kubernetes.io/name=vmalertmanager -c alertmanager --tail 50
   ```

1. If the log shows `cannot read Alertmanager notification metrics` or `no Alertmanager notification metrics`, make sure that `vmselect` runs and that VictoriaMetrics scrapes Alertmanager.

1. Make sure that vmalert and Alertmanager run:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l 'app.kubernetes.io/name in (vmalert,vmalertmanager)'
   ```

1. If a pod is not `Running`, examine its log and events.
