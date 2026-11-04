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

To silence an alert during planned work, open the Alertmanager UI:

```sh
kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y port-forward svc/vmalertmanager-vm 9093:9093
```

Then open `http://127.0.0.1:9093/#/silences` and add a silence with an end time.

## HostDown

A host does not answer the node exporter scrape for 3 minutes. The alert does not cover the NGINX VMs; see [NginxVmDown](#nginxvmdown).

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

## NginxVmDown

An NGINX VM does not answer the node exporter scrape, or `nginx.service` is not active, for 2 minutes. The `node` scrape job finds only the Linode hosts, so the alert covers only the Linode NGINX VMs until the Vultr hosts are scraped.

1. Examine NGINX on the VM:

   ```sh
   ssh freecodecamp@<instance> 'sudo nginx -t; sudo systemctl status nginx'
   ```

1. If `nginx -t` prints `test is successful`, start NGINX again:

   ```sh
   ssh freecodecamp@<instance> sudo systemctl restart nginx
   ```

1. If the VM does not answer or NGINX does not start, make sure that the VM gets no traffic:
   - Linode VM: each NodeBalancer of the environment (`prd-nb-oldeworld-pxy-1` to `-3`, `stg-nb-oldeworld-pxy`) checks the TCP connection to each NGINX VM on ports 80 and 443 every 10 seconds. After 3 failed checks, it stops sending traffic to the VM. In Linode Cloud Manager, open each NodeBalancer and make sure that the nodes of the VM show `DOWN`.
   - Vultr VM, when the Vultr hosts are scraped: in the Cloudflare dashboard, open the zone, then **DNS** > **Records**. Delete each proxied A record that points at the public IP address of the VM.

1. Repair or rebuild the VM. For a Vultr VM, add the records again.

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

Fluent Bit on a Vultr host dropped log records in the last 15 minutes. One of two causes applies:

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

An output of Fluent Bit on a Vultr host has used half of its buffer for 15 minutes. The output cannot send records to the log agent as fast as it reads them. Each output has its own limit. A full buffer drops records.

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

## NodeTargetsAbsent

The `node` scrape job has no targets for 10 minutes. The metrics of each host stop, and HostDown cannot fire.

1. Examine the log of the scrape agent:

   ```sh
   kubectl --kubeconfig k3s/ops-o11y-vultr/.kubeconfig.yaml -n o11y logs deploy/vmagent-vm -c vmagent --tail=50
   ```

1. If the log shows `401` or `403` from the cloud provider API, replace the API token that the service discovery uses.

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

## NginxHigh5xxRate

More than 5% of the requests to one `server_name` return a 5xx status for 5 minutes, with at least 100 requests in each 5 minutes.

1. Find the failing upstream in the NGINX error log. Run the query in the VictoriaLogs UI:

   ```text
   _time:15m _stream:{level=~"error|crit|alert|emerg"} upstream
   ```

1. Examine the service behind the upstream. Restart or roll back its last deploy.

## NginxUpstreamErrors

An NGINX VM logs more than 10 upstream errors in 5 minutes for 5 minutes.

1. Read the errors in the VictoriaLogs UI. Use the `host` label of the alert:

   ```text
   _time:15m _stream:{level=~"error|crit|alert|emerg",host="<host>"} upstream
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
