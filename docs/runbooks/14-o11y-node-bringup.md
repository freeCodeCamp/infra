# 14 — mgmt cluster bringup (ops-o11y)

**Audience:** operator. **Trigger:** growth of the single `ops-vm-o11y-k3s-fra1-01` node into the three-server `mgmt` cluster (T58), a later rebuild of one node, or a rebuild of the whole cluster after a total loss.

The cluster is freeCodeCamp's management plane: Rancher, Flux, External Secrets, VictoriaMetrics and Grafana. It pulls node_exporter metrics from ~80 Linode VMs over Tailscale, keeps 12 months of history, and later scrapes the Hetzner estate under the same `job="node"`. The cluster name and every path stay `ops-o11y` until the rename is decided (RFC Q21).

Every command runs from the repo root unless the line says otherwise. No `just`. Each `kubectl`, `helm` and `flux` line carries `KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml`. `terraform/ops-o11y/` and `ansible/` carry `.envrc` files, so OpenTofu lines run through `direnv exec .` in `terraform/ops-o11y/`, and Ansible lines run from `ansible/` with `INFRA_ADMIN=1 direnv exec . uv run`.

Four layers, one tool each: OpenTofu builds the droplets, Ansible builds the K3s servers, `flux install` puts Flux on the cluster, and Flux installs everything else from git. Flux reads GitHub, never a checkout, so the files under `k3s/ops-o11y/` must be pushed on the branch the GitRepository pins (`feat/bare-metal` today; flip `k3s/ops-o11y/flux-system/gitrepository.yaml` to `main` when the branch merges).

## Topology

| Item          | Value                                                                                                                                                   |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nodes         | 3 × `s-4vcpu-16gb-amd`, fra1, project `o11y`, tag `ops-o11y`; `ops-vm-o11y-k3s-fra1-01` … `-03`                                                         |
| Datastore     | embedded etcd, every node a server; local snapshots every 6 h, 20 kept                                                                                  |
| API           | tcp/6443 on the tailnet; SANs are the hostname and the tailnet address; the kubeconfig names node 01; joiners dial the first host on the VPC                                                    |
| etcd, flannel | DigitalOcean VPC on `eth1` (`--node-ip`, `--advertise-address`, `--flannel-iface=eth1`); the firewall opens the four ports between tagged droplets only |
| NodePorts     | tailnet only (`nodeport-addresses=100.64.0.0/10`); Grafana 30300, Traefik 30080/30443                                                                   |
| Storage       | DigitalOcean block storage by CSI v4.18.0 (`do-block-storage`, default class); `local-path` stays for scratch only                                      |
| Secrets       | External Secrets Operator 2.10.0 + 1Password Connect 2.4.1 (`ClusterSecretStore/onepassword`, vault `infra`)                                            |
| GitOps        | Flux v2.9.5; `GitRepository/infra` → Kustomizations `platform-controllers` → `platform-configs` → `rancher`; `cluster-dns`; `apps`                                                                   |
| Management    | Rancher 2.15.1, 3 replicas, Gateway API through the K3s Traefik, Rancher-issued CA, Fleet off                                                           |

Git layout under `k3s/ops-o11y/`:

| Path                                 | Owner                        | Content                                                                                                                                                               |
| ------------------------------------ | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flux-system/`                       | hand-applied once, then Flux | `GitRepository/infra`, the five Flux Kustomizations                                                                                                                  |
| `platform/`                          | Kustomizations `platform-controllers`, `platform-configs`, `rancher`   | `controllers/` (External Secrets, 1Password Connect, cert-manager), `configs/` (`ClusterSecretStore`, DigitalOcean CSI vendored v4.18.0), `rancher/`                                                                       |
| `cluster/coredns/`                   | Kustomization `cluster-dns`  | `coredns-custom` ConfigMap (ts.net forward)                                                                                                                           |
| `apps/`                              | Kustomization `apps`         | namespace `o11y`; per app a `HelmRepository`, a `HelmRelease`, an `ExternalSecret`, and a `configMapGenerator` over `charts/<chart>/values.yaml` + `values-mgmt.yaml` |
| `ops/`                               | hand-applied on demand       | `vmbackup-job.yaml`, `vmrestore-job.yaml`                                                                                                                             |
| `apps/*/application.yaml`, `argocd/` | Argo CD, until T58 step 5    | delete in the step-5 commit, never before                                                                                                                             |

`values-mgmt.yaml` overrides only what the three-node cluster changes: the storage class, and for Grafana the alerting contact points and SMTP. `charts/<chart>/values.yaml` stays the shared base.

## Preconditions

| #   | Requirement                                                                                                                                                                                                                                                                                                                                           | Check                                                                                                                           |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `tofu` 1.12.x on PATH; `infra-secrets/tfstate/.env.enc` carries `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`; `do-universe/.env.enc` decrypts; bucket `infra-tfstate` exists                                                                                                                                                   | `cd terraform/ops-o11y && direnv exec . tofu init`                                                                              |
| 2   | The `do-universe` token owns project `o11y`                                                                                                                                                                                                                                                                                                           | `cd terraform/ops-o11y && direnv exec . sh -c 'DIGITALOCEAN_ACCESS_TOKEN=$DIGITALOCEAN_TOKEN doctl account get --format Team'`  |
| 3   | `TAILSCALE_AUTH_KEY` in `global/.env.enc` is current (minted 2026-09-06, rotate before 2026-12-05)                                                                                                                                                                                                                                                    | `test -n "$TAILSCALE_AUTH_KEY"` under `INFRA_ADMIN=1`                                                                           |
| 4   | Tailnet ACL permits operator → nodes on tcp/6443, and `tag:added-by-ops` → `tag:added-by-ops` on 9100                                                                                                                                                                                                                                                 | the servers play, then the target count, fail without it                                                                        |
| 5   | node_exporter v1.12.1 on the fleet and on every mgmt node, bound to the tailnet address                                                                                                                                                                                                                                                               | `play-o11y--node-exporter-0-install.yml`                                                                                        |
| 6   | `helm` 3.14+, `kubectl`, `flux` v2.9.5 on PATH (`brew install fluxcd/tap/flux`); `flux` is optional, every `flux` line has a `kubectl` twin below                                                                                                                                                                                                     | `flux version --client`                                                                                                         |
| 7   | Root shell on each node by Tailscale SSH grant                                                                                                                                                                                                                                                                                                        | `ssh root@ops-vm-o11y-k3s-fra1-01 true`                                                                                         |
| 8   | The branch the GitRepository pins is pushed                                                                                                                                                                                                                                                                                                           | `git ls-remote --heads origin feat/bare-metal`                                                                                  |
| 9   | 1Password: a Connect server for vault `infra`, its `1password-credentials.json` and access token, stored as `../infra-secrets/onepassword/1password-credentials.json.enc` and `OP_CONNECT_TOKEN` in `../infra-secrets/onepassword/.env.enc`                                                                                                           | `sops -d --input-type dotenv --output-type dotenv ../infra-secrets/onepassword/.env.enc \| grep -c OP_CONNECT_TOKEN` prints `1` |
| 10  | 1Password items in vault `infra`: `mgmt-do-csi-token` (field `token`, a DigitalOcean token with block-storage write scope), `mgmt-linode-sd-token` (field `token`, scopes `linodes:read_only`, `ips:read_only`), `mgmt-grafana-alerting` (fields `GOOGLE_CHAT_WEBHOOK_URL`, `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `ALERT_EMAIL_TO`) | the three ExternalSecrets read `SecretSynced` after the platform Kustomization is Ready                                         |
| 11  | An R2 bucket for VictoriaMetrics backups, with `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`, `R2_BUCKET` in `../infra-secrets/o11y-backup/.env.enc`                                                                                                                                                                            | step 1 of the growth path fails without it                                                                                      |
| 12  | The Rancher hostname is decided and resolves on the tailnet to the three node addresses (three A records in a zone you own, or one MagicDNS name for a single node)                                                                                                                                                                                   | `dig +short <hostname>` prints `100.x` addresses                                                                                |

Preconditions 9–12 are new for the three-node cluster and are the operator's to create. Preconditions 9, 10 and 11 name proposed envelope paths and item names; if you choose other names, change `platform/onepassword-connect/clustersecretstore.yaml`, the three `externalsecret.yaml` files and the step-1 line to match.

## Fresh bringup

Use this order for a cluster built from nothing. For the growth of the live single node, use **Growth path (T58)** below instead; it interleaves these same commands with the data moves.

### 1. Droplets

```sh
cd terraform/ops-o11y && direnv exec . tofu init && direnv exec . tofu apply && cd ../..
```

`node_count` (default 3) and `size` (default `s-4vcpu-16gb-amd`) live in `terraform/ops-o11y/variables.tf`. Node `NN` is `ops-vm-o11y-k3s-fra1-NN`. Every node shares the tag, the firewall and the project link. The firewall opens tcp/22 and udp/41641 from anywhere, and tcp/6443, tcp/2379-2380, tcp/10250, udp/8472 from droplets that carry the tag. The droplet ignores later changes to `image`, `ssh_keys` and `user_data`. Rebuild one node with `direnv exec . tofu apply -replace='digitalocean_droplet.ops_o11y["02"]'` after you remove its device from the tailnet.

Wait for cloud-init on every new node:

```sh
for ip in $(cd terraform/ops-o11y && direnv exec . tofu output -json ipv4_addresses | jq -r '.[]'); do ssh freecodecamp@"$ip" sudo cloud-init status --wait; done
```

### 2. Tailnet and K3s

From `ansible/`:

```sh
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-tailscale--0-install.yml          -e variable_host=ops_o11y
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-tailscale--1a-up.yml              -e variable_host=ops_o11y
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--servers.yml                  -e variable_host=ops_o11y
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-o11y--node-exporter-0-install.yml -e variable_host=ops_o11y
```

`play-k3s--servers.yml` reads the K3s version from the first host of the group when one runs, and from `k3s_version` in `inventory/group_vars/ops_o11y.yml` on a fresh cluster (RFC Q22). The first host gets `--cluster-init`; the others join it over the VPC. The play installs the Gateway API CRDs v1.4.0, writes the Traefik `HelmChartConfig`, saves an etcd snapshot named `play-<n>-servers`, and writes `k3s/ops-o11y/.kubeconfig.yaml`. A second run reports `changed=0` for every host.

`k3s_init_host` in `inventory/group_vars/ops_o11y.yml` names the node that holds the datastore. The play asserts that it is the first host of the inventory group and inside `--limit`, and stops otherwise. Inventory order is the DigitalOcean plugin's, so this guard is what stops a second `--cluster-init` on the wrong node.

### 3. Bootstrap secrets

Three Secrets are not in git and Flux never creates them. Create the two Connect Secrets before Flux is installed; a HelmRelease that waits on a missing Secret times out and stops after three retries. Values reach `kubectl` through the environment or a temporary file outside the worktree; no line prints a value.

1Password Connect credentials and token, in namespace `external-secrets`:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl create namespace external-secrets --dry-run=client -o yaml \
  | KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f -
umask 077; CRED=$(mktemp)
sops -d --output-type json ../infra-secrets/onepassword/1password-credentials.json.enc > "$CRED"
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n external-secrets create secret generic op-credentials \
  --from-file=1password-credentials.json="$CRED" --dry-run=client -o yaml \
  | KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f -
rm -f "$CRED"
```

```sh
set -a; eval "$(sops -d --input-type dotenv --output-type dotenv ../infra-secrets/onepassword/.env.enc)"; set +a
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n external-secrets create secret generic op-connect-token \
  --from-literal=token="$OP_CONNECT_TOKEN" --dry-run=client -o yaml \
  | KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f -
unset OP_CONNECT_TOKEN
```


### 4. Flux

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux install --version=v2.9.5
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -k k3s/ops-o11y/flux-system
```

On the growth path, suspend `apps` at once: the Argo CD workloads still run in `o11y`, and a Helm install over them fails on ownership. Step 7 resumes it.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux suspend kustomization apps
```

Without the `flux` CLI, the first line is `KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f https://github.com/fluxcd/flux2/releases/download/v2.9.5/install.yaml`; the content is the same. `infra` is public, so the GitRepository carries no credential. This is the T62 decision: `flux install` plus committed sources, no `flux bootstrap`, pushes stay the operator's.

Then watch the platform land in order: `platform-controllers` (External Secrets, Connect, cert-manager) → `platform-configs` (`ClusterSecretStore`, CSI with its token as an ExternalSecret) → `rancher`.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n flux-system get kustomizations,gitrepositories
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get helmreleases -A
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get clustersecretstore onepassword
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get externalsecrets -A
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get storageclass
```

Every Kustomization and HelmRelease reads `Ready=True`; the store and every ExternalSecret read `Ready`; `do-block-storage` is `(default)`. The `rancher` HelmRelease is suspended in git until step 6 and reads `Suspended`.

### 5. Apps and CoreDNS

The `apps` Kustomization waits on `platform-configs` and `cluster-dns`, so nothing here needs a hand. Restart CoreDNS once after the ConfigMap lands and prove `ts.net` resolves from the pod network:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system rollout restart deployment coredns
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n kube-system run dnscheck --rm -it --restart=Never \
  --image=busybox:1.37 -- nslookup ops-vm-o11y-k3s-fra1-01.batfish-ray.ts.net
```

Then the Verify section.

### 6. Rancher

Rancher is the last piece and is suspended in git until its hostname exists (precondition 12). Replace `hostname: CHANGEME` in `k3s/ops-o11y/platform/rancher/helmrelease.yaml`, remove `suspend: true`, commit, push, and reconcile:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux reconcile kustomization rancher --with-source
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n cattle-system rollout status deployment rancher --timeout=600s
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n cattle-system get gateway,httproute
```

The UI is `https://<hostname>:30443` over Tailscale. Traefik terminates TLS with the certificate cert-manager issued from the Rancher-generated CA (`ingress.tls.source: rancher`), so the browser warns once; import the CA from the `tls-rancher` Secret in `cattle-system` into your trust store. At the first login the page asks for the server URL; enter `https://<hostname>:30443`. The bootstrap password:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n cattle-system get secret bootstrap-secret -o go-template='{{ .data.bootstrapPassword | base64decode }}{{ "\n" }}'
```

Rancher runs three replicas with required anti-affinity, one per node, so one node off keeps the UI up.

## Growth path (T58)

The live single node runs SQLite K3s, Argo CD, and `local-path` volumes on its root disk. This path grows it in place. `[H]` marks a line only the operator runs (Terraform, node changes, secrets); `[A]` marks a line an agent may run against the cluster. Do the steps in order; each has an exit check.

### Step 1 `[H]` — back the data up

Argo CD must not see this change; the Job lives outside `apps/*/application.yaml`. Create the R2 credential Secret from the envelope (precondition 11), run the backup Job on the current volume, and copy the two files that no backup tool covers.

```sh
set -a; eval "$(sops -d --input-type dotenv --output-type dotenv ../infra-secrets/o11y-backup/.env.enc)"; set +a
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y create secret generic vm-backup-r2 \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_ENDPOINT_URL_S3="$AWS_ENDPOINT_URL_S3" --from-literal=R2_BUCKET="$R2_BUCKET" \
  --dry-run=client -o yaml | KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f -
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 R2_BUCKET
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f k3s/ops-o11y/ops/vmbackup-job.yaml
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y wait --for=condition=complete job/vmbackup --timeout=30m
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y logs job/vmbackup | tail -3
```

`vmbackup` asks VictoriaMetrics for a snapshot over HTTP and uploads it, so the database keeps running. The Job mounts the same `local-path` claim, which pins it to node 01.

```sh
mkdir -p k3s/ops-o11y/.backups && umask 077
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y cp "$(KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')":/var/lib/grafana/grafana.db k3s/ops-o11y/.backups/grafana.db
ssh root@ops-vm-o11y-k3s-fra1-01 'systemctl stop k3s && cp /var/lib/rancher/k3s/server/db/state.db /root/state.db.pre-etcd && systemctl start k3s'
scp root@ops-vm-o11y-k3s-fra1-01:/root/state.db.pre-etcd k3s/ops-o11y/.backups/state.db.pre-etcd
```

`k3s/ops-o11y/.backups/` is gitignored. The stop-copy-start takes about 20 s of API outage and gives a consistent SQLite file.

Exit check: the Job is `Complete`, `.backups/` holds both files, and `KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y delete job vmbackup` leaves the namespace as it was.

### Step 2 `[H]` — resize and add droplets

```sh
cd terraform/ops-o11y && direnv exec . tofu plan && direnv exec . tofu apply && cd ../..
```

The plan shows node 01 resized to `s-4vcpu-16gb-amd` in place (a power-off and on), nodes 02 and 03 created, and four firewall rules added. Nothing is destroyed; stop if the plan says otherwise. Wait for cloud-init on 02 and 03 (fresh-bringup step 1), then join them to the tailnet:

```sh
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-tailscale--0-install.yml -e variable_host=ops_o11y
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-tailscale--1a-up.yml     -e variable_host=ops_o11y
```

Exit check: `tailscale status | grep ops-vm-o11y` lists three devices; `KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get nodes` still shows one `Ready` node with 16 GB (`kubectl describe node … | grep memory:`).

### Step 3 `[H]` — convert node 01 to etcd

The servers play with `--limit` on node 01 alone rewrites its unit with `--cluster-init` and restarts K3s, which converts the SQLite datastore in place (docs.k3s.io/datastore/ha-embedded, "Existing single-node clusters"). The same run moves `--node-ip` to the VPC address and enables Traefik.

```sh
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--servers.yml -e variable_host=ops_o11y -l ops-vm-o11y-k3s-fra1-01
```

Exit check, in this order:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get nodes -o wide
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n argocd get applications
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get pvc
ssh root@ops-vm-o11y-k3s-fra1-01 'k3s etcd-snapshot ls'
```

One `Ready` node whose `INTERNAL-IP` is now `10.110.0.2`; five Applications `Synced`; two PVCs `Bound`; one snapshot `play-1-servers-…`. If the Applications or the PVCs are missing, roll back and stop:

```sh
ssh root@ops-vm-o11y-k3s-fra1-01 'systemctl stop k3s && rm -rf /var/lib/rancher/k3s/server/db/etcd && cp /root/state.db.pre-etcd /var/lib/rancher/k3s/server/db/state.db && sed -i "s/--cluster-init //" /etc/systemd/system/k3s.service && systemctl daemon-reload && systemctl start k3s'
```

### Step 4 `[H]` — join 02, then 03

One node per run, node 01 always in the limit. Each run saves a snapshot.

```sh
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--servers.yml -e variable_host=ops_o11y -l ops-vm-o11y-k3s-fra1-01,ops-vm-o11y-k3s-fra1-02
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--servers.yml -e variable_host=ops_o11y
INFRA_ADMIN=1 direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-o11y--node-exporter-0-install.yml -e variable_host=ops_o11y
```

Exit check: three `Ready` nodes at `v1.36.4+k3s1`; `k3s etcd-snapshot ls` on node 01 lists three `play-*` snapshots; `count(up{job="o11y-node"})` stays 1: the job is a static target list in the VictoriaMetrics values and names node 01 only. Extend it to the three nodes as a follow-up.

### Step 5 `[A]` — remove Argo CD

Argo CD's Applications carry a resources finalizer: deleting an Application with the controller running deletes everything it tracks. Stop the controller first, then strip the finalizers, then delete. The workloads stay.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n argocd scale statefulset argocd-application-controller --replicas=0
for app in root argocd cluster-dns grafana victoria-metrics; do
  KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n argocd patch application "$app" --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
done
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n argocd delete applications --all
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml helm uninstall argocd -n argocd
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl delete namespace argocd
```

Then the git side, as one commit made now and not before: delete `k3s/ops-o11y/apps/*/application.yaml`, `k3s/ops-o11y/apps/argocd/` and `k3s/ops-o11y/argocd/`. A push of that deletion while Argo CD still runs prunes the live workloads.

Exit check: `kubectl get ns argocd` reports not found; `kubectl -n o11y get statefulset,deployment` still lists VictoriaMetrics and Grafana.

### Step 6 `[A]` for Flux, `[H]` for the secrets

Fresh-bringup steps 3 and 4, in that order, with the `apps` suspend. Watch `platform-controllers` and `platform-configs` reach Ready.

### Step 7 `[A]` — move the apps to Flux and block storage

Argo CD wrote no Helm release Secrets, so Flux cannot adopt the running releases, and the StatefulSet's volume claim template cannot change class in place. Hours have passed since step 1, so back up again first (the step-1 Job lines; `vmbackup` uploads only what changed, and the `grafana.db` copy overwrites the old one). Then remove the old namespace with its `local-path` volumes, let Flux create the releases fresh on block storage, then restore.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl delete namespace o11y
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux resume kustomization apps
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get pvc
```

Both PVCs are `Bound` on `do-block-storage`. Now stop VictoriaMetrics, restore, start:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux suspend helmrelease victoria-metrics -n o11y
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y scale statefulset victoria-metrics-victoria-metrics-single-server --replicas=0
```

Re-create `vm-backup-r2` with the step-1 lines (the namespace was deleted), then:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl apply -f k3s/ops-o11y/ops/vmrestore-job.yaml
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y wait --for=condition=complete job/vmrestore --timeout=30m
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y delete job vmrestore secret vm-backup-r2   # the ExternalSecret re-creates vm-backup-r2
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y scale statefulset victoria-metrics-victoria-metrics-single-server --replicas=1
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux resume helmrelease victoria-metrics -n o11y
```

The `kubectl` twins of the `flux` lines are `kubectl -n o11y patch helmrelease victoria-metrics --type merge -p '{"spec":{"suspend":true}}'` and the same with `false`. Grafana: copy the database back and restart the pod.

```sh
GRAFANA_POD=$(KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y cp k3s/ops-o11y/.backups/grafana.db "$GRAFANA_POD":/var/lib/grafana/grafana.db
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y rollout restart deployment grafana
```

Exit check: `count(up{job="node"})` reads the same value as before step 1 (80 at the time of writing), a query over the last 7 days returns history, and Grafana shows the same dashboards and admin login.

### Step 8 `[H]` — Rancher and alerting

Fresh-bringup step 6 for Rancher. Grafana alerting is already provisioned by `apps/grafana/values-mgmt.yaml` from the `grafana-alerting` ExternalSecret: contact points `ops-chat` (Google Chat) and `ops-email`, a default policy to chat, `severity=page` also to email. Send a test notification from **Alerting → Contact points** for both.

Then the T58 verify list: Rancher UI up with one droplet powered off (`doctl compute droplet-action power-off <id>`, then on); every HelmRelease Ready; the fleet count unchanged; `k3s etcd-snapshot ls` shows three `play-*` snapshots.

### Rename

The name `ops-o11y` stays through T58. A rename to `mgmt` touches the droplet names, the tailnet devices, the DO tag and firewall, the inventory group, `k3s/ops-o11y/`, the Terraform state key and this runbook; do it as its own commit after Rancher has imported `prd` and `stg` (T12), when the name is worth its cost, or never.

## Verify

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get nodes -o wide
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n flux-system get kustomizations
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get helmreleases -A
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get externalsecrets -A
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y get pvc
```

Three `Ready` nodes; every Kustomization and HelmRelease `Ready`; every ExternalSecret `SecretSynced`; PVCs on `do-block-storage`. Then the fleet count against the inventory:

```sh
(cd ansible && ansible-inventory -i inventory/linode.yml --list | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["_meta"]["hostvars"]))')
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y exec statefulset/victoria-metrics-victoria-metrics-single-server -- \
  wget -qO- 'http://127.0.0.1:8428/api/v1/query?query=count(up{job="node"}==1)'
```

The two numbers match. The target-list detail, the label sanity check and the failure table from the single-node era are unchanged: port-forward 8428 and read `/api/v1/targets` (expect `node` 80, `o11y-node` 3, `vmsingle` 1, `dropped` 0, `off-tailnet` 0).

Grafana: <http://ops-vm-o11y-k3s-fra1-01:30300> over Tailscale, or any node's name. The admin password is generated into the `grafana` Secret on first install and reused on every upgrade; the step-7 database copy carries the old password.

## Storage and backups

Block storage volumes follow the pod to any node, which is what makes a node loss survivable. Retention is still the guard: `--retentionPeriod=12` and `--storage.minFreeDiskSpaceBytes=20GB` on a 50 Gi volume. Grow the claim in `values-mgmt.yaml` (`server.persistentVolume.size`); the CSI resizes the volume online.

Backups are `vmbackup` to R2: the CronJob `vmbackup` in `apps/victoria-metrics/` runs daily at 03:17 UTC with the keys from the `vm-backup-r2` ExternalSecret (1Password item `mgmt-r2-backup`), and the Job in `ops/` is the hand-run copy before a risky change. Both write incrementally to the same prefix. The etcd snapshots are local to the nodes; `etcd-s3` to a bucket is a follow-up too. Read the disk after seven and thirty days:

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl -n o11y exec statefulset/victoria-metrics-victoria-metrics-single-server -- df -h /storage
```

## Teardown

Suspend Flux, remove the releases, then the droplets. PVCs on block storage are deleted with the namespace; the R2 backup is the only copy after that.

```sh
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux suspend kustomization apps rancher platform-configs platform-controllers cluster-dns
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl delete -k k3s/ops-o11y/flux-system
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml flux uninstall
cd terraform/ops-o11y && direnv exec . tofu destroy && cd ../..
```

Delete the three devices in the tailnet admin console, then revoke the tokens: the DigitalOcean CSI token and the Linode token in 1Password, and the R2 key. Revocation is the only real erase.

## Known limits

- **VictoriaMetrics and Grafana are one replica each.** A node loss reschedules them onto another node with the same volume; expect a gap of a few minutes, not a lost history. The fleet does not notice a dead collector, which is still the accepted trade.
- **Rancher's hostname is a value in git.** It carries the port `30443`, because Traefik is a NodePort on the tailnet. Do not open 443 on the firewall to remove the port; the tailnet-only posture is the design.
- **The tailnet suffix is hard-coded** as `batfish-ray.ts.net` in the VictoriaMetrics values. A tailnet rename breaks all 80 targets at once.
- **Linode label must equal the Tailscale hostname.** A rebuilt host that re-registers as `<name>-1` fails at DNS while its label is unchanged.
- **A powered-off Linode stays a target** and reports `up=0`. That is the host-down signal.
- **No alert rules yet.** Contact points and the policy exist; the capacity rules from the single-node era (`vm_storage_is_read_only`, free disk under `1.5 × vm_free_disk_space_limit_bytes`, root filesystem under 25 %, `vm_promscrape_discovery_linode_failures_total > 0`, `count(up{job="node"}) < 75`) are the first rules to write, as provisioned `rules.yaml` under `alerting`.
- **6443 and 10250 bind `0.0.0.0`.** The DigitalOcean firewall is their only control from the internet; between droplets the four tagged rules are the control. A host firewall for `100.64.0.0/10` only is the non-breaking second layer.
- **No PSS labels on the `o11y` namespace.** Upstream charts; compliance untested.

## Cross-doc references

- [`00-index.md`](00-index.md) — runbook index
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — sops envelopes
- <https://docs.k3s.io/datastore/ha-embedded> — the in-place SQLite → etcd conversion
- <https://fluxcd.io/flux/installation/> — `flux install`
- <https://external-secrets.io/latest/provider/1password-automation/> — the Connect provider
- <https://docs.victoriametrics.com/victoriametrics/vmbackup/> — `vmbackup` and `vmrestore`
