# 14 — Observability node bringup (ops-o11y)

**Audience:** operator. **Trigger:** first bringup of `ops-vm-o11y-k3s-fra1-01`, or a rebuild of that node after a total loss.

This node is freeCodeCamp's first infrastructure observability plane. It pulls node_exporter metrics from ~80 Linode VMs over Tailscale, keeps 12 months of history, and later scrapes the Hetzner bare-metal estate under the same `job="node"` so one dashboard spans the provider migration.

Every command below runs from the repo root. No `just`. `terraform/ops-o11y/` and `ansible/` carry `.envrc` files that load their envelopes, so the OpenTofu lines run through `direnv exec .` in `terraform/ops-o11y/`, and the Ansible lines run from `ansible/` with `INFRA_ADMIN=1`, which loads `global/.env.enc` and with it the tailnet auth key. Each `kubectl` and `helm` line carries its own `KUBECONFIG=`.

## Topology, and why

**Pull, not push.** `vmagent` is not deployed. VictoriaMetrics single-node scrapes the fleet directly through `-promscrape.config`, which the chart wires from `server.scrape.enabled`. The 80 production hosts run no agent that targets this node, so when this node dies the fleet does not notice. That is the accepted single point of failure, recorded deliberately: this node is not highly available.

**One process, not two.** A separate `vmagent` would add a Deployment, a ConfigMap, an HTTP hop and a `remoteWrite` disk buffer. That buffer only protects against a dead remote endpoint, which cannot happen when agent and storage share one node. The fleet is ~98k active series against a documented single-node envelope of 50M+.

**Service discovery, not a static list.** `linode_sd_configs` enumerates the estate from the Linode API every minute. A static target list was rejected: the estate has already drifted once, with 8 live VMs absent from infrastructure-as-code.

**Addresses are rewritten, and the rewrite is enforced.** Linode SD sets `__address__` to the public IPv4, falling back to the private IPv4 on Linode's shared regional network. node_exporter binds Tailscale-only, so a relabel rule rewrites `__address__` to `<linode-label>.batfish-ray.ts.net:9100`. The Linode label is the Tailscale hostname on all 80 hosts. That rewrite is a `replace` gated on a non-empty label, so on any non-match it is a silent no-op that would leave a Linode-routable address in place — a final `keep` rule on `__address__` therefore drops any target that did not land on the tailnet. It fails closed.

**This node monitors itself.** Two static jobs, `vmsingle` and `o11y-node`, sit alongside the discovered `node` job. This is not a retreat from service discovery: SD still enumerates the whole fleet, and these two targets are the one machine SD cannot find, because it is a DigitalOcean droplet that `linode_sd_configs` will never return. Without them the single point of failure is the only host invisible to the monitoring it runs, and every capacity alert below has no series to fire on.

## Preconditions

| #   | Requirement                                                                                                                         | Check                                              |
| --- | ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| 1   | `tofu` 1.12.x on PATH, `infra-secrets/tfstate/.env.enc` and `do-universe/.env.enc` decrypt, R2 bucket `infra-tfstate` exists | `cd terraform/ops-o11y && tofu init`               |
| 1a  | The vault's `TAILSCALE_AUTH_KEY` in `global/.env.enc`, owned by `tag:added-by-ops` and not expired (check under Settings, Keys in the admin console) | `test -n "$TAILSCALE_AUTH_KEY"`                    |
| 2   | Tailnet ACL permits operator → node on tcp/6443                                                                                     | step 1 below fails without it                      |
| 3   | Tailnet ACL permits node → fleet on tcp/9100                                                                                        | step 5 verification fails without it               |
| 4   | node_exporter v1.12.1 on the fleet, bound to the Tailscale address, port 9100                                                       | separate Ansible task; not this runbook            |
| 5   | Linode API token, scopes `linodes:read_only` and `ips:read_only`                                                                    | mint at <https://cloud.linode.com/profile/tokens>  |
| 6   | `helm` >= 3.14 and `kubectl` on PATH                                                                                                | `helm version --short && kubectl version --client` |
| 7   | Root shell on the node, by Tailscale SSH grant or key                                                                               | `ssh root@ops-vm-o11y-k3s-fra1-01 true`            |
| 8   | node_exporter v1.12.1 on this node too, bound to its Tailscale address, port 9100                                                   | separate Ansible task; step 5 counts it            |

Precondition 8 is easy to skip. This node is the one host whose disk and memory the whole design turns on, and without its own node_exporter it is the only machine in the estate that the monitoring cannot see.

Preconditions 2, 3, 4 and 8 are outside this repo. Confirm them before starting; each one fails late and looks like a different problem.

Precondition 7 is easy to miss. Tailscale SSH refuses any identity the tailnet policy does not grant, and `/etc/rancher/k3s/k3s.yaml` is mode 0600 root-owned, so a non-root login needs `sudo cat` in step 1. Steps 1, 6, the disk-budget reading and teardown all need this shell.

## Provision

The node is code. OpenTofu creates the droplet, its tag-attached firewall and the project link; Ansible joins the tailnet and installs K3s. Every line runs from the repo root.

```sh
cd terraform/ops-o11y && direnv exec . tofu init && direnv exec . tofu apply && cd ../..
```

State lives in R2 (`infra-tfstate`, key `ops-o11y/terraform.tfstate`) with S3-native locking. On the first `apply` after a hand-built node, the tag `ops-o11y` may already exist in the account; delete it first (`doctl compute tag delete ops-o11y`) or `tofu import digitalocean_tag.ops_o11y ops-o11y`. Delete the old firewall too — DigitalOcean permits two firewalls with one name, and both would apply.

The firewall opens tcp/22 and udp/41641 at create, so Ansible reaches the node over its public IPv4 at once. Then, from `ansible/` with `INFRA_ADMIN=1` in the environment:

```sh
ansible-playbook -i inventory/digitalocean.yml play-tailscale--0-install.yml -e variable_host=ops_o11y
ansible-playbook -i inventory/digitalocean.yml play-tailscale--1a-up.yml     -e variable_host=ops_o11y
ansible-playbook -i inventory/digitalocean.yml play-k3s--single-node.yml     -e variable_host=ops_o11y
ansible-playbook -i inventory/digitalocean.yml play-o11y--stack-0-deploy.yml -e variable_host=ops_o11y
```

The key's tag owns the device, so the node joins as `ops-vm-o11y-k3s-fra1-01` with no key expiry. If a device of that name is still in the tailnet, remove it in the admin console first, or the node joins as `-1` and the MagicDNS name in `values.yaml` stops resolving.

## Steps

> **The playbooks are the mechanism. These steps are the explanation and the fallback.**
>
> ```sh
> ansible-playbook -i inventory/digitalocean.yml play-k3s--single-node.yml     -e variable_host=ops_o11y
> ansible-playbook -i inventory/digitalocean.yml play-o11y--stack-0-deploy.yml -e variable_host=ops_o11y
> ```
>
> The first bootstraps the node and writes the kubeconfig, superseding **step 1** and
> **step 6** — do not apply step 6's config block by hand, because
> `play-k3s--single-node.yml` owns `/etc/rancher/k3s/config.yaml` and will revert it.
> The second reconciles CoreDNS, the namespace, the service-discovery Secret and every
> Helm release, superseding **steps 2, 3, 4, 7** and **9**. Add
> `-e o11y_deploy_logs=true` for VictoriaLogs.
>
> **Step 5 needs T38.** It verifies fleet targets are up, and nothing has `node_exporter`
> until the rollout playbook has run. Expect 80 targets down before then.
>
> Read the steps below to understand what the playbooks do, to verify afterwards, or to
> recover by hand when a playbook cannot run.

### 1. Kubeconfig

The kubeconfig is not in git and there is no sops envelope for this cluster. Pull it off the node and rewrite the server address to the tailnet IP.

```sh
umask 077
ssh root@ops-vm-o11y-k3s-fra1-01 cat /etc/rancher/k3s/k3s.yaml > k3s/ops-o11y/.kubeconfig.yaml
NODE_IP=$(tailscale ip -4 ops-vm-o11y-k3s-fra1-01)
sed -i '' "s|server: https://127.0.0.1:6443|server: https://${NODE_IP}:6443|" k3s/ops-o11y/.kubeconfig.yaml
chmod 600 k3s/ops-o11y/.kubeconfig.yaml
```

On Linux drop the `''` after `sed -i`.

Verify:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get nodes -o wide
```

One `Ready` node. Record its `INTERNAL-IP` — step 6 needs to know whether it is the tailnet address.

### 2. CoreDNS forwards ts.net

Scrape targets are MagicDNS names, so the cluster resolver must forward `ts.net` to the Tailscale resolver. K3s imports this optional ConfigMap into its managed Corefile.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f k3s/ops-o11y/cluster/coredns/coredns-custom.yaml
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system rollout restart deployment coredns
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system rollout status deployment coredns --timeout=120s
```

Prove resolution works from inside the pod network before deploying anything that depends on it:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system run dnscheck --rm -it --restart=Never \
  --image=busybox:1.37 -- nslookup ops-vm-o11y-k3s-fra1-01.batfish-ray.ts.net
```

Expect a `100.x.y.z` answer. If it fails, see **Fallback: pod cannot reach the tailnet** below. Do not continue past this point on a failure — every target will be down.

Now prove the whole scrape path in one shot, against any fleet host. This turns a precondition 3 or 4 failure into an error here rather than into "80 targets down" at step 5:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system run scrapecheck --rm -it --restart=Never \
  --image=busybox:1.37 -- wget -qO- --timeout=5 http://prd-vm-oldeworld-clt-eng-0.batfish-ray.ts.net:9100/metrics
```

Expect node_exporter's `# HELP` preamble. A hang or refusal means the tailnet ACL does not permit node → fleet on tcp/9100, or node_exporter is not installed on that host yet.

### 3. Namespace and the Linode token

All three releases share the `o11y` namespace.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl create namespace o11y
```

The token never enters git and never reaches disk. Read it into the shell, hand it to `kubectl` through a file that holds the key name only, then drop both.

```sh
umask 077
read -rs LINODE_API_TOKEN && export LINODE_API_TOKEN
TOKEN_FILE=$(mktemp)
printf 'LINODE_API_TOKEN\n' > "$TOKEN_FILE"
```

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y create secret generic vm-linode-sd \
  --from-env-file="$TOKEN_FILE"
```

```sh
rm -f "$TOKEN_FILE"; unset LINODE_API_TOKEN
```

A line with no `=` makes `kubectl` take that key's value from the environment (`kubectl` `pkg/cmd/util/env_file.go`), so the temporary file contains a key name and nothing else.

Do not copy `.secrets.env.sample` and fill it in. It is the tracked schema and stays empty; a filled copy inside the worktree is one `git add -A` away from a committed credential, and editor backups (`.secrets.env~`, `#.secrets.env#`) are exactly the names a narrow ignore pattern misses. There is deliberately no secure-erase step here: no file ever holds the value, and on an APFS or any copy-on-write filesystem an overwrite-in-place erase would not be a guarantee anyway. The only real erase is revoking the token at <https://cloud.linode.com/profile/tokens>.

The Secret key `LINODE_API_TOKEN` becomes the mounted filename. The scrape config reads `/etc/vm/secrets/LINODE_API_TOKEN`; renaming the key silently breaks service discovery.

Confirm the key name without printing the value:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y describe secret vm-linode-sd
```

Expect one entry, `LINODE_API_TOKEN`, with a byte count.

### 4. VictoriaMetrics

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm upgrade --install victoria-metrics victoria-metrics-single \
  --repo https://victoriametrics.github.io/helm-charts --version 0.45.0 \
  -n o11y \
  -f k3s/ops-o11y/apps/victoria-metrics/charts/victoria-metrics-single/values.yaml
```

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y rollout status statefulset victoria-metrics-victoria-metrics-single-server --timeout=300s
```

Chart 0.45.0 ships appVersion v1.150.0; `server.image.tag` pins the running binary to v1.151.0. `linode_sd_configs` needs v1.150.0 or newer, so there is no downgrade path below this chart generation.

Confirm the tag and the retention flags:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get statefulset victoria-metrics-victoria-metrics-single-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}'
```

Expect `victoriametrics/victoria-metrics:v1.151.0`, `--retentionPeriod=12`, `--storage.minFreeDiskSpaceBytes=20GB`, `--storage.maxDailySeries=500000`, `--search.maxConcurrentRequests=2`, `--search.maxMemoryPerQuery=512MB`, `--search.logQueryMemoryUsage=256MB` and `--promscrape.config=/scrapeconfig/scrape.yml`.

The query bounds are deliberate and they are visible to users. Two concurrent queries at 512 MB each caps the query term at ~1 GB inside a 3Gi limit that also holds ~1.8 GiB of cache. A wide dashboard that fires more than two panels at once queues (`-search.maxQueueDuration`, default 10s) and then returns 503. If that becomes routine, raise `search.maxConcurrentRequests` one step at a time and watch memory — do not remove the bound. `--storage.maxDailySeries=500000` drops new series beyond that count in a rolling 24 hours and logs each drop; it is a runaway guard against veth churn, not a tuning knob, and ~98.4k active series sits far below it.

### 5. Verify the targets are up

Service discovery is lazy about auth: a wrong token gives a running pod with zero targets and no crash. Count the targets explicitly, and prove every fleet target resolved onto the tailnet.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y port-forward svc/victoria-metrics-victoria-metrics-single-server 8428:8428 &
PF_PID=$!
sleep 3
```

```sh
curl -s http://127.0.0.1:8428/api/v1/targets | python3 -c '
import json,sys,collections
d=json.load(sys.stdin)["data"]
t=d["activeTargets"]
print("by job:", dict(sorted(collections.Counter(x["labels"]["job"] for x in t).items())))
print("health:", dict(collections.Counter(x["health"] for x in t)))
print("dropped:", len(d["droppedTargets"]))
for x in t:
    if x["health"] != "up":
        print("  DOWN", x["labels"].get("instance"), x.get("lastError","")[:120])
bad=[x for x in t if x["labels"]["job"] == "node" and ".batfish-ray.ts.net:9100" not in x["scrapeUrl"]]
print("off-tailnet:", len(bad), [x["scrapeUrl"] for x in bad][:5])
'
```

Expect `by job: {'node': 80, 'o11y-node': 1, 'vmsingle': 1}`, `health: {'up': 82}`, `dropped: 0` and `off-tailnet: 0`.

`off-tailnet` proves the invariant is armed rather than catching a leak: Linode SD hands out the public IPv4, a relabel rule rewrites it to the tailnet name, and a final `keep` rule drops any target that rewrite missed. A miss therefore shows up as a _missing_ target and a non-zero `dropped` count, never as a scrape over a Linode-routable path.

Sanity-check the label set that the relabel rules produce:

```sh
curl -s 'http://127.0.0.1:8428/api/v1/query?query=count%20by%20(role)%20(up%7Bjob%3D%22node%22%7D)'
```

That is `count by (role) (up{job="node"})`. Expect `clt` 48, `api` 12, `nws` 7, `jms` 6, `pxy` 6, `backoffice` 1. The job filter keeps this node's own two targets out of the fleet counts. Then stop the forward:

```sh
kill "$PF_PID"
```

**Reading a failure:**

| Symptom                                       | Cause                                                                                                                                                                   |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| no `node` targets                             | Token wrong, expired, or missing the `ips:read_only` scope. Query `vm_promscrape_discovery_linode_failures_total` — the `vmsingle` self-scrape job stores it.           |
| 80 `node` targets, all down, `no such host`   | Step 2 did not take. Re-run the `nslookup` check.                                                                                                                       |
| 80 `node` targets down, refused or timing out | Tailnet ACL blocks node → fleet tcp/9100, or node_exporter is not installed yet (precondition 3 or 4).                                                                  |
| Fewer than 80 `node` targets, `dropped: 0`    | Real estate drift. That is the discovery working, not a fault.                                                                                                          |
| Fewer than 80 `node` targets, `dropped` > 0   | The tailnet `keep` rule removed a target whose Linode label was empty, so `__address__` was never rewritten. Read `droppedTargets[].discoveredLabels` in the same JSON. |
| `o11y-node` down, the 80 fleet targets up     | Precondition 8 — node_exporter is not on this node yet. Expected on a first run before the Ansible task has covered it.                                                 |

### 6. Node config — NodePort binding and reserved memory

Two node-level settings that no Helm value can carry: pin which node IPs a NodePort binds, and stop the scheduler treating k3s itself as free memory.

Create or edit `/etc/rancher/k3s/config.yaml` on the node — the node was installed with CLI flags, so the file may not exist yet — and add both blocks:

```yaml
kube-proxy-arg:
  - "nodeport-addresses=100.64.0.0/10"
kubelet-arg:
  - "system-reserved=cpu=500m,memory=1.5Gi"
```

```sh
ssh root@ops-vm-o11y-k3s-fra1-01 systemctl restart k3s
```

Set `nodeport-addresses` even if the node's `INTERNAL-IP` is already the tailnet address. kube-proxy has no default for it; when unset, NodePort connections are accepted on every local IP in every proxy backend (kube-proxy 1.36, `cmd/kube-proxy/app/options.go`). Setting it is the only thing that restricts the binding. The DigitalOcean firewall (UDP 41641 only) is the outer control; this is defence in depth.

`system-reserved` reserves capacity the scheduler may not hand to pods. k3s sets no reservation of its own, so without this the k3s server, containerd and the kubelet are invisible to scheduling on a node whose whole risk is that it is one node. This only shrinks allocatable — the default `enforceNodeAllocatable` is `pods` alone, so nothing puts the k3s process itself under a new cgroup limit.

Verify both took. NodePort first — `ss -lntp` cannot answer this, because modern kube-proxy opens no listening socket for a NodePort. Read the proxy rules directly; this node's backend is whichever k3s v1.36.4 chose, so try both and expect the `100.64.0.0/10` destination match in one of them:

```sh
ssh root@ops-vm-o11y-k3s-fra1-01 'iptables-save -t nat | grep -A2 KUBE-NODEPORTS'
ssh root@ops-vm-o11y-k3s-fra1-01 'nft list table ip kube-proxy | grep -i nodeport'
```

Then the reservation:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl describe node ops-vm-o11y-k3s-fra1-01 | grep -A8 -E '^(Capacity|Allocatable)'
```

Allocatable memory must sit exactly 1.5 GiB below Capacity. Nothing else is subtracted: k3s v1.36.4 sets `EvictionHard` to `imagefs.available: 5%` and `nodefs.available: 5%` only (`pkg/daemons/agent/agent.go`), and that map _replaces_ the kubelet default, so there is no `memory.available` threshold to reserve. Before this change the two figures are therefore identical — if they still are, the restart did not pick the file up.

### 7. Grafana

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm upgrade --install grafana grafana \
  --repo https://grafana-community.github.io/helm-charts --version 13.1.0 \
  -n o11y \
  -f k3s/ops-o11y/apps/grafana/charts/grafana/values.yaml
```

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y rollout status deployment grafana --timeout=300s
```

`--repo` is mandatory. The `grafana` chart in `grafana/helm-charts` was deprecated at 10.5.15 and moved to `grafana-community`; a stale local `grafana` repo alias silently installs the old one.

No admin password is set anywhere. The chart generates one into the `grafana` Secret on first install and reuses the existing value on every later upgrade, so the credential never enters git and never rotates underneath you. Read it once, store it in the team password manager, and do not delete that Secret — deleting it regenerates the password on the next upgrade.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get secret grafana \
  -o go-template='{{ index .data "admin-password" | base64decode }}'
```

### 8. Reach the UI

<http://ops-vm-o11y-k3s-fra1-01:30300> — over Tailscale, plain HTTP inside the WireGuard tunnel. Log in as `admin` with the password from step 7.

Both datasources are provisioned from values, so no clicking is needed:

- **VictoriaMetrics** (default) — type `prometheus`, no plugin. VictoriaMetrics serves a Prometheus-compatible API. This trades MetricsQL-only syntax for zero plugin dependency.
- **VictoriaLogs** — type `victoriametrics-logs-datasource`, plugin pinned at 0.31.0 and downloaded at pod start. It stays red until step 9 runs. That is expected.

Confirm the metrics datasource is live: **Connections → Data sources → VictoriaMetrics → Save & test**. Then graph `count(up{job="node"})` and expect 80, and `count(up)` and expect 82 — the extra two are this node's own node_exporter and vmsingle itself.

If Grafana crash-loops on start, the plugin download failed — the pod needs egress to `grafana.com`. Remove the `plugins` block and the VictoriaLogs datasource from values, redeploy, and restore both when step 9 runs.

Now prove step 6 held, from the node itself. The first must fail and the second must succeed:

```sh
ssh root@ops-vm-o11y-k3s-fra1-01 'PUB=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address); TS=$(tailscale ip -4); \
  curl -s -o /dev/null -w "public %{http_code}\n" --max-time 5 "http://$PUB:30300"; \
  curl -s -o /dev/null -w "tailnet %{http_code}\n" --max-time 5 "http://$TS:30300"'
```

Expect the public probe to time out or refuse and the tailnet probe to return `302` or `200`. A `200` on the public address means the NodePort is answering on the public interface and the DigitalOcean firewall is the only thing between a Grafana admin login and the internet — go back to step 6.

### 9. VictoriaLogs — deferred, optional

**Do not run this on day one.** Check memory headroom before you do anything else here — this step adds a 1Gi limit on a node that already carries 3Gi for VictoriaMetrics and 512Mi for Grafana, against roughly 6.2 GiB allocatable after step 6's reservation:

```sh
ssh root@ops-vm-o11y-k3s-fra1-01 'free -m'
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl top node ops-vm-o11y-k3s-fra1-01
```

The `available` column of `free -m` must read at least 1500. If it does not, this step trades the metrics database for logs on a node with no replica — stop and reduce the VictoriaMetrics limit first, or do not run this step.

VictoriaLogs has no pull mode. Every ingestion path is an agent on the source host pushing into this node, which re-creates exactly the topology rejected for metrics: 80 agents buffering to local disk against a dead endpoint. Shipping fleet logs is a separate operator decision about the accepted single point of failure, not a config change.

Run it only after VictoriaMetrics has produced a real disk-growth curve, and only when the log source is decided.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm upgrade --install victoria-logs victoria-logs-single \
  --repo https://victoriametrics.github.io/helm-charts --version 0.13.9 \
  -n o11y \
  -f k3s/ops-o11y/apps/victoria-logs/charts/victoria-logs-single/values.yaml
```

The values set `retentionMaxDiskUsagePercent: 80` and deliberately leave `retentionDiskSpaceUsage` empty. The two are mutually exclusive — setting both makes VictoriaLogs refuse to start — and percent is chosen _because_ it measures the whole filesystem holding `-storageDataPath`. Both databases share the 160 GB root disk, and VictoriaMetrics stops accepting writes at `--storage.minFreeDiskSpaceBytes=20GB`. At 80% used VictoriaLogs begins dropping its oldest per-day partitions with ~32 GB still free, comfortably above that floor, so logs yield before metrics ingestion stops. A bytes-only cap would have given VictoriaLogs no awareness of the filesystem at all.

Accept the trade knowingly: the percent cap counts _total_ filesystem usage, not VictoriaLogs' share. If VictoriaMetrics data and its index alone ever push the disk past 80%, VictoriaLogs deletes every partition it has and still does not clear the threshold. That is the intended priority — metrics outrank logs — but it should not be a surprise when it happens.

## Disk budget

The 160 GB root filesystem is shared by the OS, containerd and both databases. `local-path` ignores PVC capacity, so the PVC sizes below are the design expectation, not enforcement. The real guards are the retention flags, and one of the four rows is a reservation rather than a consumer.

| Consumer / reservation             | Setting                                        | Budget  | Guard                                                                              |
| ---------------------------------- | ---------------------------------------------- | ------- | ---------------------------------------------------------------------------------- |
| VictoriaMetrics                    | `retentionPeriod: 12`, PVC `50Gi`              | 53.7 GB | `--storage.minFreeDiskSpaceBytes=20GB` stops ingestion before full                 |
| VictoriaLogs                       | `retentionMaxDiskUsagePercent: 80`, PVC `32Gi` | 34.4 GB | the percent flag, not the PVC — see below                                          |
| Grafana                            | `persistence 2Gi`                              | 2.1 GB  | none needed                                                                        |
| OS + containerd + k3s              | —                                              | ~20 GB  | —                                                                                  |
| VictoriaMetrics free-space reserve | `--storage.minFreeDiskSpaceBytes=20GB`         | 20 GB   | space nothing may ever occupy; it must be in the sum, not only in the Guard column |

That totals ~130.2 GB of 160 GB, leaving ~30 GB of real margin.

The VictoriaLogs row is a budget, not a ceiling. The percent guard fires on total filesystem usage, so VictoriaLogs can legitimately grow past 32 GiB while the disk is quiet and will be forced back below it once metrics grow. Do not read `kubectl get pvc` as a capacity statement.

~98,400 active series at a 60s interval is ~1,640 samples/s, ~142M samples/day. 12 months retention means up to 13 months on disk. At 0.75 B/sample that is ~42 GB of _samples_ — and zero bytes of inverted index. The index is the part nobody budgets: `-retentionTimezoneOffset` documents that indexdb rotation happens once per `-retentionPeriod`, so at 12 months the index rotates once a year and the previous generation is held alongside the current one. Every unique series minted in that window stays indexed for up to two years, and the Docker Swarm hosts mint series that never repeat — veth device names are per container instance, so each deploy adds ~35 series that never merge back.

**Measure before extending, and measure the index separately.** Take a reading after seven days and again after thirty:

```sh
ssh root@ops-vm-o11y-k3s-fra1-01 'df -h /; du -sh /var/lib/rancher/k3s/storage/*; du -sh /var/lib/rancher/k3s/storage/*/data/indexdb'
```

Graph `vm_indexdb_items_added_size_bytes_total` alongside it — the `vmsingle` self-scrape job stores it.

Extending `retentionPeriod` on existing data is safe and is the intended path once real numbers exist. Do not raise it speculatively, and note what the blocker actually is: not the sample term, which is arithmetic and already known, but index growth under veth churn. Thirty days of readings sample the first month of a 365-day monotonic index curve and cannot extrapolate to a 13-month figure. Only a full rotation cycle answers it. `--storage.maxDailySeries=500000` is the runaway guard in the meantime; it drops and logs excess new series rather than letting churn take the disk.

### Disk full

If the filesystem does fill, the node cannot recover on its own. This is worth stating plainly because the usual Kubernetes safety net does not apply here.

The kubelet reclaims _node-level_ resources under disk pressure — it deletes unused images and evicts pods. PersistentVolume bytes under `/var/lib/rancher/k3s/storage/` are neither ephemeral storage nor reclaimable that way. k3s sets `nodefs.available: 5%` rather than the kubelet's own default, so the taint lands at ~8 GB free on this filesystem, and `EvictionMinimumReclaim` then asks for another 10% the kubelet cannot take from a PV. The node taints `DiskPressure:NoSchedule`, deletes images, evicts pods, and the pressure never clears, because evicting a database pod frees none of that database's bytes. That 5% is not a safety net on this node.

Ordered by free space on the 160 GB filesystem, the guards fire like this: at 32 GB free VictoriaLogs drops its oldest partitions (80% used); at 20 GB free VictoriaMetrics goes read-only and metrics ingestion stops; at 8 GB free the kubelet declares DiskPressure and cannot fix it; at 0 the SQLite datastore behind k3s and containerd start taking ENOSPC. Only the first two are recoveries; the last two are damage.

VictoriaMetrics clears its own read-only state only when free space rises, which means waiting for a monthly partition delete up to a month away, and only if it was the filler. The exits are manual: shell in and delete per-day partition directories under the storage path, or delete the PVC and lose the history. Catch it earlier with the capacity alerts under Known limits.

## Fallback: pod cannot reach the tailnet

If step 2's `nslookup` fails, CoreDNS cannot reach `100.100.100.100` from the pod network. Diagnose before changing the design:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system logs deployment/coredns --tail=50
```

```sh
ssh root@ops-vm-o11y-k3s-fra1-01 'ip route get 100.100.100.100; tailscale status --peers=false'
```

If the node itself resolves and the pod does not, the gap is flannel masquerading pod traffic onto `tailscale0`. The escape hatch is to move the scrape into the host network namespace, which means swapping this design for a `vmagent` DaemonSet writing into VictoriaMetrics:

- Deploy `victoria-metrics-agent` 0.46.0 with `mode: daemonSet`, `hostNetwork: true`, `dnsPolicy: ClusterFirstWithHostNet`, `image.tag: v1.151.0`, and this repo's `scrape_configs` moved under `config`. That chart mounts the scrape config at a different path: `/config/scrape/scrape.yml`.
- `hostNetwork: true` renders **only** when `mode: daemonSet`. In `deployment` or `statefulSet` the chart drops it with no error and no warning.
- Set `extraArgs.httpListenAddr: "127.0.0.1:8429"`. With `hostNetwork` the agent would otherwise bind 8429 on the public interface.
- Turn off `server.scrape.enabled` in the VictoriaMetrics values and point the agent's `remoteWrite` at `http://victoria-metrics-victoria-metrics-single-server.o11y.svc:8428/api/v1/write`.
- The `o11y-node` job moves across unchanged. The `vmsingle` job does not: `127.0.0.1:8428` is the vmsingle pod only from inside that pod, and under `hostNetwork` it resolves to the node. Re-target it at the vmsingle Service, or self-monitoring silently disappears along with every capacity alert below.

Take this branch only on evidence. It is strictly more moving parts.

## Teardown

`helm uninstall` leaves StatefulSet PVCs behind by design. Deleting them destroys all history — that is why they are listed separately.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm uninstall grafana -n o11y
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm uninstall victoria-logs -n o11y
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm uninstall victoria-metrics -n o11y
```

Stop here for a redeploy that keeps history. Re-running steps 4, 7 and 9 reattaches the same volumes.

To destroy the data as well:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y delete pvc \
  server-volume-victoria-metrics-victoria-metrics-single-server-0 \
  server-volume-victoria-logs-victoria-logs-single-server-0 \
  grafana --ignore-not-found
```

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y delete secret vm-linode-sd --ignore-not-found
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl delete namespace o11y
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system delete configmap coredns-custom --ignore-not-found
```

Then revert the node changes: remove both the `kube-proxy-arg` and the `kubelet-arg` blocks from `/etc/rancher/k3s/config.yaml`, restart k3s, and revoke the Linode API token at <https://cloud.linode.com/profile/tokens>. Revocation is the only real erase — deleting the Secret does not invalidate the credential.

If the Hetzner estate has joined by then, its Robot credentials are a separate credential with a separate revocation path: retire them at <https://robot.hetzner.com> as well. They are higher value than a read-only Linode token.

To remove the node itself, destroy it from the root that created it, then delete the device in the tailnet admin console:

```sh
cd terraform/ops-o11y && tofu destroy && cd ../..
```

Confirm nothing survives:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get pvc -A
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get ns o11y
```

## Known limits

- **Not highly available.** One node, no replicas, no PodDisruptionBudgets. A node loss stops collection and the gap is permanent. Recorded operator decision.
- **The tailnet suffix is hard-coded** as `batfish-ray.ts.net` in the VictoriaMetrics values. A tailnet rename breaks all 80 targets at once.
- **Linode label must equal the Tailscale hostname.** True for all 80 today. A rebuilt host that re-registers under a name collision becomes `<name>-1`, and its target then fails at DNS while its Linode label is unchanged. Worth a nightly drift check comparing Linode labels against tailnet peer names.
- **A powered-off Linode stays a target** and reports `up=0`. That is the host-down signal. There is deliberately no `drop` rule on `__meta_linode_status`, because dropping would make a broken host vanish from the dashboard instead of alerting.
- **No alerting is deployed.** `vmalert` and a notifier are not part of this bringup. Capacity is the whole risk on a node with no replica, so write the capacity rules first. All five need the `vmsingle` and `o11y-node` self-scrape jobs, which is why they exist.
  1. `vm_storage_is_read_only == 1` — metrics ingestion has already stopped. Page on this.
  2. `vm_free_disk_space_bytes < 1.5 * vm_free_disk_space_limit_bytes` — the warning before that floor.
  3. `node_filesystem_avail_bytes{instance="ops-vm-o11y-k3s-fra1-01",mountpoint="/"} / node_filesystem_size_bytes{instance="ops-vm-o11y-k3s-fra1-01",mountpoint="/"} < 0.25` — the whole filesystem, including anything that is not a database.
  4. `vm_promscrape_discovery_linode_failures_total > 0` — service discovery is failing; the target list is going stale.
  5. `count(up{job="node"}) < 75` — the fleet, or the tailnet path to it, is degraded.
- **Only NodePort is pinned to the tailnet.** k3s binds the API server (tcp/6443) and the kubelet (tcp/10250) on `0.0.0.0` by default, and those are the highest-value ports on the node — step 1 copies a cluster-admin kubeconfig off 6443. The DigitalOcean firewall is their only control today. A host firewall permitting 6443 and 10250 from `100.64.0.0/10` only is the non-breaking way to add a second layer. Do not set `bind-address` in the k3s config instead: k3s writes `server: https://127.0.0.1:6443` into `/etc/rancher/k3s/k3s.yaml`, so rebinding away from `0.0.0.0` breaks `kubectl` on the node itself, which step 1 and the disk-budget readings depend on.
- **No PSS labels on the `o11y` namespace.** Sibling clusters set `pod-security.kubernetes.io/enforce: restricted` from their own chart templates. These are upstream charts, so that convention does not carry. Compliance is untested — a follow-up, not part of this bringup.
- **Docker Swarm hosts inflate series counts.** The 12 `api` and 6 `jms` hosts add one veth interface per container at ~35 series each. If such a host exceeds ~1,600 series, exclude `veth` from the netdev and netclass collectors on the node_exporter side.

## Cross-doc references

- [`00-index.md`](00-index.md) — runbook index
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — sops envelopes; this node loads `tfstate/` and `do-universe/` through `terraform/ops-o11y/.envrc`
- <https://docs.victoriametrics.com/victoriametrics/sd_configs/> — `linode_sd_configs` and `hetzner_sd_configs` reference
