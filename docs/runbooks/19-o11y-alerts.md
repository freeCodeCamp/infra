# 19 — o11y alerts (ops-o11y-vultr)

**Audience:** operator. **Trigger:** an alert from the `ops-o11y-vultr` cluster arrives in Google Chat, or the Sentry Cron Monitor of the Watchdog reports a missed check-in.

Each alert has one section here. The section name is the alert name. The alert links to its section in the `runbook_url` annotation.

Run every command from the repo root unless the step says otherwise.

## Preconditions

- Your shell is on the tailnet.
- `k3s/ops-o11y-vultr/.kubeconfig.yaml` exists.

## See the alerts that fire

Open the vmalert UI of the metric rules:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y port-forward svc/vmalert-vm 8880:8080
```

Then open `http://127.0.0.1:8880/vmalert/alerts`. For the log rules, use `svc/vmalert-vlogs` in place of `svc/vmalert-vm`.

To read logs, open the VictoriaLogs UI at `http://<o11y node>:30427/select/vmui` and log in.

To see traffic, errors, probes and host health, open Grafana at `http://<o11y node>:30300` and log in with the 1Password item `o11y-grafana-admin` (vault `Infra-IaC-ESO`, fields `username` and `password`). Grafana does not start without this item. The home page is the dashboard **Traffic and health**. The folder **freeCodeCamp** also has **Fleet capacity and stability**. The folders **VictoriaMetrics** and **Hosts** have the upstream dashboards. These are files in `k3s/ops-o11y-vultr/cluster/grafana/dashboards/upstream/`, so Grafana starts without GitHub. They come from `VictoriaMetrics/VictoriaMetrics` at `29c43cd2`, `VictoriaMetrics/VictoriaLogs` at `915d9190` and `rfmoz/grafana-dashboards` at `b07d8a90`, with the panels removed whose metrics we do not collect. Grafana alerting is off; all alerts come from vmalert through Alertmanager.

To silence an alert during planned work, open the Alertmanager UI:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y port-forward svc/vmalertmanager-vm 9093:9093
```

Then open `http://127.0.0.1:9093/#/silences` and add a silence with an end time.

## Test the alert path

This test proves that an alert reaches the Google Chat space. It does not prove that the rule expression is correct. People in the space see the messages, so tell them first.

1. Read the list of alerts that the test sends:

   ```sh
   k3s/ops-o11y-vultr/tools/alert-drill.sh --dry-run
   ```

1. Send the alerts:

   ```sh
   k3s/ops-o11y-vultr/tools/alert-drill.sh --send
   ```

1. In the Google Chat space, make sure that one message with `Drill-` in its title comes for each alert in the list, in about 1 minute. About 16 minutes after you send, each alert gets a message or a thread reply that ends in `Resolved`. Do not send again during this time: Alertmanager merges the alerts and posts no new messages.
1. Test the Watchdog. Add a silence with the matcher `alertname="Watchdog"` and an end time of 1 hour. The CronJob stops its check-ins, and Sentry reports a missed check-in. While the silence is on, each run of the CronJob fails with `Watchdog is not active; no check-in`, and the last 3 failed Jobs stay in the `o11y` namespace. This is correct.
1. When Sentry reports it, expire the silence. Make sure that the Sentry monitor becomes OK at the next check-in.

To add the names of the log alerts (`NginxHigh5xxRate`, `NginxUpstreamErrors`), give their file after `--dry-run` or `--send`: `k3s/ops-o11y-vultr/cluster/victoria-logs/vmrule-logs.yaml`. This test does not use `vmalert-vlogs`, so it does not prove the path from `vmalert-vlogs` to Alertmanager.

## HostDown

A host does not send metrics for about 5 minutes. The alert does not cover the NGINX VMs; see [NginxVmDown](#nginxvmdown).

- The host has sent metrics in the last day, but not in the last 2 minutes. Fluent Bit on the host reads the node exporter and sends the metrics. If Fluent Bit stops, this alert fires.
- A destroyed or rebuilt Vultr VM alerts until it sends again or until it has been gone for 1 day. Silence the alert for that `instance` before you destroy the VM.

1. Connect to the host. Use the `instance` label of the alert:

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

## NginxVmDown

An NGINX VM does not send metrics, or `nginx.service` is not active, for about 4 minutes. The rule for a missing host is the same as in [HostDown](#hostdown).

1. Examine NGINX on the VM:

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

## FluentBitDroppedRecords

Fluent Bit on a Vultr host dropped log records or metrics in the last 15 minutes. The `name` label names the output: `http.*` sends logs to the log agent, `prometheus_remote_write.*` sends metrics to vmagent. One of two causes applies:

- The log agent refused the records with an HTTP 4xx status. Fluent Bit keeps a copy in `/var/lib/fluent-bit/storage/rejected`, up to 256M.
- The buffer of an output became full, and Fluent Bit removed the oldest records. Those records are lost.

1. Find the cause. Use the `instance` label of the alert:

   ```sh
   ssh freecodecamp@<instance> 'sudo journalctl -u fluent-bit --since -30min --no-pager | grep -E "HTTP status=|will not be retried"'
   ```

1. If the output shows `will not be retried`, the log agent refused the records. Read the status on the line before it, then examine the log of the log agent:

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

1. A connection error shows a fault in the VPC network or the node. An HTTP 5xx status shows a fault in the log agent.

## VultrMetricsPushDown

No Vultr host has sent metrics for 2 minutes, for 5 minutes. HostDown and NginxVmDown do not fire for the Vultr hosts while this alert fires. Each Vultr host sends its metrics to port 30428 on `fluent_bit_vlagent_host` (`ansible/inventory/group_vars/provider_vultr.yml`). Fluent Bit keeps up to 256M of metrics on disk and sends them when the receiver is back.

1. Make sure that the o11y node at that address is `Ready`, and that vmagent runs:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get nodes -o wide
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get svc vmagent-vm
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l app.kubernetes.io/name=vmagent
   ```

   The Service must show `8429:30428/TCP`.

1. Examine the Fluent Bit log on one Vultr host:

   ```sh
   ssh freecodecamp@<host> 'sudo journalctl -u fluent-bit --since -30min --no-pager | grep prometheus_remote_write | tail -20'
   ```

## TargetDown

A scrape target that is not a host, such as a cluster component or an exporter, is down for 5 minutes.

1. Find the pod of the target. Use the `job` and `instance` labels of the alert:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml get pods -A -o wide
   ```

1. Examine the pod events and the log, then delete the pod so that it starts again.

## ProbeFailed

A public hostname fails the HTTP probe for 3 minutes. The `instance` label is the URL.

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

1. If the log rules fail, make sure that the VictoriaLogs pod that they read runs:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l app.kubernetes.io/instance=vlogs-a
   ```

1. If a rule expression is wrong, correct the rule in git. Argo CD syncs the fix.

## O11yBackupStale

A nightly backup to R2 has not succeeded for 36 hours. The `cronjob` label names it. Examine the last Job, then see [21-o11y-backup-restore.md](21-o11y-backup-restore.md):

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get jobs --sort-by=.metadata.creationTimestamp
```

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

The Watchdog alert always fires. A CronJob sends a Sentry check-in each 5 minutes while the Watchdog is active in Alertmanager. If Sentry reports a missed check-in, the alert path is broken.

1. Examine the CronJob runs:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get jobs --sort-by=.metadata.creationTimestamp
   ```

1. Make sure that vmalert and Alertmanager run:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y get pods -l 'app.kubernetes.io/name in (vmalert,vmalertmanager)'
   ```

1. If a pod is not `Running`, examine its log and events.
