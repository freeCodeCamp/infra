# Ansible Plays

The plays in `ansible/` and the commands that replace the `justfile` (removed 2026-10-14).

## Before You Start

Run the play commands from `ansible/`. Run the former `just` recipes from the repository root. direnv loads the Vultr token and puts `ansible/.venv/bin` on `PATH`, so `ansible-*` commands need no `uv run`.

```bash
cd ansible
uv sync --locked
.venv/bin/ansible-galaxy install -r requirements.yml
```

On a fresh clone, direnv adds `ansible/.venv/bin` to `PATH` only after `uv sync` and the next `cd` into the repository. The first `ansible-galaxy` call uses the full path for this reason.

Each clone and worktree has its own `.venv` and `.ansible/collections`. Run the two install commands again in each new clone or worktree, and after a pull that changes `pyproject.toml`, `uv.lock` or `requirements.yml`. A stale copy fails in the middle of a play, for example with `Failed to import the required Python library (netaddr)`.

Show the groups:

```bash
ansible-inventory -i inventory/digitalocean.yml --graph
ansible-inventory -i inventory/vultr.yml -i inventory/constructed.yml --graph
```

The Vultr inventory needs `VULTR_API_KEY`. `ansible/.envrc` loads it from `vultr/.env.enc` when that envelope exists and `CLAUDECODE` is not set. With no key, the inventory gives `HTTP Error 401: Unauthorized`. With no key or no `vultr.cloud` collection, the inventory has no hosts, and the play stops with `Could not match supplied host pattern`.

The DigitalOcean inventory needs the `DO_API_TOKEN` of the main team. `ansible/.envrc` does not load it. Run each DigitalOcean command in the subshell of [runbook 04](../runbooks/04-secrets-decrypt.md#3-run-commands-with-the-secrets-in-the-environment-dotenv-only), step 3. From `ansible/`, the envelope path is `../../infra-secrets/do-primary/.env.enc`.

## Rules for Every Play

- Give the target group with `-e variable_host=<group>`. `play-swarm--form.yml` is different: it takes `swarm_manager_group` and `swarm_worker_group`.
- A group name that does not exist stops the play with `Could not match supplied host pattern`. If you forget `-e variable_host`, the name in the message is `null`.
- In GitHub Actions, a group with no hosts gives a warning and the play does nothing. With the `vultr` provider, the run fails on a group with no hosts or a group name that does not exist, because a Vultr group exists only when a host matches it. The `update` and `reboot` workflows take `check: true` to run with `--check`.
- `ansible--housekeeping.yml` and `ansible--cleanup-clients.yml` name a group and a provider on each job leg. An environment moves to Vultr at its traffic cutover, by a change to its legs.
- Most plays that change hosts do one host at a time and stop at the first host that fails. Some take `-e variable_serial=<n>`. These are different:
  - `play-any--cleanup-clients.yml` does all hosts at the same time and does not stop on a failed host.
  - `play-any--verify-nginx.yml` and the other k3s plays do all hosts at the same time. `play-k3s--reboot.yml` and the node probe in `play-k3s--verify-o11y.yml` do one host at a time and ignore `variable_serial`. If the peer node is unreachable after the drain, it stops and leaves the node cordoned; uncordon it by hand.
- Add `--check` to see the changes without making them. `play-any--cleanup-clients.yml`, `play-clients--restart.yml` and `play-clients--rollback.yml` also take `-e variable_dry_run=true`.
- Each run adds its output to `ansible/.ansible/ansible.log`.

The command form:

```bash
ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml <play> -e variable_host=<group> [-e <input>=<value>]
```

## Host Plays

| Play                                | What it does                                                              | Changes hosts | Inputs                                                                                                                                                                                                  |
| ----------------------------------- | ------------------------------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `play-any--uptime.yml`              | Show the uptime                                                           | No            | —                                                                                                                                                                                                       |
| `play-any--check-disk-space.yml`    | Report disk and inode use                                                 | No            | `variable_disk_threshold`, `variable_inode_threshold`, `variable_disk_fstypes`                                                                                                                          |
| `play-any--verify-nginx.yml`        | Check that NGINX runs and starts at boot. Restart it once if it is down.  | Restart only  | `variable_nginx_port`                                                                                                                                                                                   |
| `play-any--update.yml`              | Upgrade the packages                                                      | Yes           | `variable_serial`                                                                                                                                                                                       |
| `play-any--reboot.yml`              | Reboot when the host needs it, then wait for it                           | Yes           | `variable_force_reboot=true`, `variable_serial`                                                                                                                                                         |
| `play-any--restart-docker.yml`      | Restart Docker, then wait for it                                          | Yes           | `variable_force_restart=true`, `variable_serial`                                                                                                                                                        |
| `play-any--fail2ban.yml`            | Install and configure fail2ban                                            | Yes           | `variable_serial`                                                                                                                                                                                       |
| `play-any--cleanup-clients.yml`     | Delete old client releases                                                | Yes           | `variable_dry_run`, `variable_serial`, `variable_client_root`                                                                                                                                           |
| `play-any--cleanup-jms.yml`         | Clean up the JMS clients                                                  | Yes           | `variable_serial`                                                                                                                                                                                       |
| `play-any--git-patch.yml`           | Apply a patch to a Git repository on the host                             | Yes           | `variable_patch_file`, `variable_repo_dir` (both required), `variable_followup_script`, `variable_followup_force=true` (runs the script also when the patch is already applied), `variable_source_envs` |
| `play-clients--list-releases.yml`   | List the client releases                                                  | No            | —                                                                                                                                                                                                       |
| `play-clients--restart.yml`         | Restart the PM2 client services                                           | Yes           | `variable_dry_run`                                                                                                                                                                                      |
| `play-clients--rollback.yml`        | Point the clients to an earlier release                                   | Yes           | `variable_client_binaries_id` (required), `variable_dry_run`, `variable_client_root`                                                                                                                    |
| `play-clients--update-config.yml`   | Pull the client config repository                                         | Yes           | `variable_clone`, `variable_serial`                                                                                                                                                                     |
| `play-clients--nodejs-0-update.yml` | Update Node.js, the global packages and PM2                               | Yes           | `variable_nodejs_version`                                                                                                                                                                               |
| `play-clients--pm2-update.yml`      | Move PM2 and its unit to the default Node.js                              | Yes           | —                                                                                                                                                                                                       |
| `play-tailscale--0-install.yml`     | Install Tailscale                                                         | Yes           | `variable_serial`                                                                                                                                                                                       |
| `play-tailscale--1a-up.yml`         | Connect to the tailnet. Keeps the current Tailscale SSH setting and tags. | Yes           | `op` signed in (reads the Tailscale auth key) or `-e tailscale_auth_key=<key>`, `variable_ssh=true\|false`, `variable_tags`                                                                             |
| `play-tailscale--2-add-cert.yml`    | Get the HTTPS certificate for the tailnet name                            | Yes           | `variable_tailnet_dns_name` (required)                                                                                                                                                                  |
| `play-tailscale--9-down.yml`        | Disconnect from the tailnet                                               | Yes           | `variable_serial`                                                                                                                                                                                       |
| `play-test--2-node-version.yml`     | Show the Node.js, npm and PM2 versions                                    | No            | —                                                                                                                                                                                                       |

## Swarm Docker Plays

Run these on the Swarm node groups. The role `docker` applies the same guard to Vultr hosts.

| Play                             | What it does                                                                                                                                        | Changes hosts | Inputs                                                                  |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | ----------------------------------------------------------------------- |
| `play-swarm--docker-guard.yml`   | Install the stray overlay device cleanup that runs before Docker starts, and hold the Docker packages. It does not restart Docker.                  | Yes           | `variable_serial`                                                       |
| `play-swarm--verify.yml`         | Check that each node is active with no stray overlay device. Then check the services from the manager.                                              | No            | `variable_service_prefix`, `variable_manager`, `variable_swarm_retries` |
| `play-swarm--upgrade-docker.yml` | Upgrade the held Docker packages on one node at a time, hold them again, and run the same checks after each node. This restarts Docker on the node. | Yes           | `variable_service_prefix`, `variable_manager`, `variable_swarm_retries` |

The default of `variable_manager` is `ops_swarm_mgr`.

`play-any--update.yml` and `play-vultr--base.yml` turn off unattended upgrades with `/etc/apt/apt.conf.d/99-no-unattended-upgrades`, so OS changes come only from housekeeping. `play-any--update.yml` does not upgrade held packages. To upgrade Docker, run `play-swarm--upgrade-docker.yml`. Start with a staging group:

```bash
ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml \
  play-swarm--upgrade-docker.yml -e variable_host=stg_api \
  -e variable_manager=ops_swarm_mgr -e variable_service_prefix=stg-
```

## DigitalOcean k3s Plays

Use `-i inventory/digitalocean.yml` in the subshell with `../../infra-secrets/do-primary/.env.enc` (see the inventory note above). For the Vultr o11y cluster, run `play-k3s--servers.yml` with `-i inventory/vultr.yml -i inventory/constructed.yml -e variable_host=ops_o11y_vultr`.

| Play                        | What it does                                                            | Inputs                                                      |
| --------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------- |
| `play-k3s--servers.yml`     | Install or upgrade k3s on `ops_o11y_vultr`, and set the AppArmor sysctl | —                                                           |
| `play-k3s--reboot.yml`      | Reboot K3s nodes one by one, with a node probe and the gate after each  | `variable_force_reboot=true`                                |
| `play-k3s--verify-o11y.yml` | Run the gate once, then the node probe on each node. Changes nothing.   | —                                                           |
| `play-k3s--longhorn.yml`    | Install Longhorn on `tools_k3s`                                         | —                                                           |
| `play-k3s--teardown.yml`    | Remove k3s from every host in the group. Takes an etcd snapshot first.  | `confirm_teardown=<group>` (required), `skip_snapshot=true` |

### The o11y Gate and Node Probe

- The AppArmor sysctl is `kernel.apparmor_restrict_unprivileged_unconfined=0` in `/etc/sysctl.d/20-apparmor.conf`. Without it, containers on kernel 7.0.0-43 cannot signal themselves (Launchpad 2172746). Remove it when Ubuntu ships a fix.
- The node probe runs pod `k3s-node-probe-<node>` on the node. The pod sends itself `SIGHUP` and must end in phase `Succeeded`.
- The gate (`tasks/k3s-o11y-gate.sh`) needs every o11y Deployment, StatefulSet and DaemonSet ready, and no o11y container, apart from Job pods, terminated in the last 15 min. After a reboot, the play waits up to 120 x 10 s for it.
- To check the cluster by hand, run `ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml play-k3s--verify-o11y.yml -e variable_host=ops_o11y_vultr` from `ansible/`.
- `ansible--reboot-k3s.yml` has no force input. To force a gated reboot, add `-e variable_force_reboot=true` to a local run of `play-k3s--reboot.yml`.

`play-k3s--servers.yml` saves a `play-` etcd snapshot, then keeps only the newest `k3s_etcd_play_snapshot_retention` of them, on the host and in R2. K3s retention does not remove a manual snapshot. To keep only the newest 3 manual snapshots, run `sudo k3s etcd-snapshot prune --name on-demand --etcd-snapshot-retention 3 --etcd-s3-retention 3` on the node that saved them. It prunes the local `on-demand` files of that node, and every `on-demand` object in R2 from any node. Give both flags: without `--etcd-s3-retention`, R2 keeps the `etcd-s3-retention` count from the group vars (60).

## Vultr Plays

| Play                                    | What it does                                                                                                                                                                                                                                                                                                         | Inputs                                                                                                                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `play-vultr--base.yml`                  | Configure the base of a Vultr host, one host at a time. Stop on a host with no internet. On the first run on a host, upgrade the packages and reboot when the host needs it. Remove ufw. Give `freecodecamp` sudo, Bash and the `docker` group. Install fail2ban, Docker, node exporter and Fluent Bit. Harden sshd. | `variable_host=<group>`, `variable_serial=<n>`. `--tags login_user` runs only the shell and group steps.                                                                                |
| `play-vultr--clients.yml`               | Prepare a client host for `deploy-client.yml`: Node.js, PM2, `serve`, the `client-config` checkout and the PM2 unit. Serves nothing until a deploy. To move Node.js later, run `play-clients--nodejs-0-update.yml`.                                                                                                  | `variable_host=<group>`, `variable_serial=<n>`                                                                                                                                          |
| `play-swarm--form.yml`                  | Form the Vultr Swarm and join the workers, then apply the node labels (runbook 18)                                                                                                                                                                                                                                   | `swarm_manager_group=<group>`, `swarm_worker_group=<group>[:<group>…]`, `swarm_rejoin=true` for a worker that is in another Swarm                                                       |
| `play-vultr--fluent-bit.yml`            | Install Fluent Bit and write its config on a Vultr host, one host at a time. The host sends its logs and its metrics to o11y.                                                                                                                                                                                        | `variable_host=<group>`, `variable_serial=<n>`                                                                                                                                          |
| `play-vultr--render-maps.yml`           | Read each VPC address. Write the NGINX upstream map (plain, to encrypt). Stops when a host of the fleet has no address.                                                                                                                                                                                              | `maps_env=stg\|prd`, `maps_write=upstreams`                                                                                                                                             |
| `play-vultr--manager.yml`               | Prepare the Swarm manager for deploys: `age`, the `~/infra` checkout and its `~/docker-swarm-config` link, `~/.docker`, and the `svc:swarm-wh-vultr` Tailscale Service.                                                                                                                                              | `variable_host=ops_swarm_mgr`. Join the tailnet first with `play-tailscale--0-install.yml` and `play-tailscale--1a-up.yml` with `-e variable_tags=tag:added-by-ops,tag:deployment-tgt`. |
| `play-vultr--o11y-tailnet-services.yml` | Serve each web UI in `o11y_tailnet_services` (`svc:grafana`, `svc:argocd-o11y`) on the o11y nodes as a Tailscale Service, to the live ClusterIP of its Kubernetes Service. Stops when a host serves a Service to another target.                                                                                     | `variable_host=ops_o11y_vultr`                                                                                                                                                          |
| `play-vultr--nginx.yml`                 | Install and start NGINX on a Vultr proxy. Write the Origin CA files and the upstream blocks.                                                                                                                                                                                                                         | `variable_host=<group>`. Reads `docker/vultr/pxy-origin-tls.yaml.enc` and `docker/vultr/pxy-upstreams-<tier>.yaml.enc`.                                                                 |

### Configure a Vultr Environment

Run the steps in this order. No step moves traffic. Cloudflare sends traffic to a proxy only after a DNS record names it ([traffic runbook](https://github.com/freeCodeCamp/terraform-cloudflare/blob/main/cf-origin-records/README.md), private repo).

1. Run `play-vultr--base.yml` on each host of the environment. On a new VM, the play first upgrades the packages, waits up to 30 minutes for the apt lock, and reboots when the upgrade needs it. Then it writes `/var/lib/freecodecamp-first-configure`. A host with this file skips the upgrade. If the upgrade or the reboot fails, the next run does them again. The image build deletes the file, so each VM made from the image does the upgrade once. A host configured before this step has no file, so its next base run upgrades it and can reboot it. On a host that serves traffic, run the base play in a maintenance slot.
2. Run `play-swarm--form.yml`.
3. Define `svc:swarm-wh-vultr` once. In the Tailscale admin console, open **Services**, select **Advertise**, then **Define a Service**. Set the endpoint `tcp:443` and the tag `tag:services`.
4. Run `play-tailscale--0-install.yml` and `play-tailscale--1a-up.yml` on `ops_swarm_mgr`, then `play-vultr--manager.yml`. In **Services**, select the Service and **Approve** its host.
5. Make the two envelopes of the proxies. Do step 6 for each file.
   - `pxy-origin-tls`: a YAML map `nginx_tls_files`, one key for each file in `/etc/nginx/ssl` (`dhparam.pem`, `freecodecamp.dev.crt`, `freecodecamp.dev.key`, `freecodecamp.org.crt`, `freecodecamp.org.key`). The play refuses a map that lacks a key.
   - `pxy-upstreams-<tier>`: `play-vultr--render-maps.yml -e maps_env=<tier> -e maps_write=upstreams` writes the plaintext file.
6. From `../infra-secrets`, encrypt the file and delete the plaintext. The command writes a temporary file and replaces the envelope only when `sops` succeeds, so a second run cannot empty the envelope:

   ```bash
   sops -e --input-type yaml --output-type yaml docker/vultr/<name>.yaml.plaintext > docker/vultr/<name>.yaml.enc.tmp && mv docker/vultr/<name>.yaml.enc.tmp docker/vultr/<name>.yaml.enc
   rm -P docker/vultr/<name>.yaml.plaintext
   ```

   Commit the envelope at once.

7. Run `play-vultr--nginx.yml -e variable_host=<tier>_pxy`.
8. Run `play-vultr--clients.yml -e variable_host=<tier>_clt`. The client hosts join the tailnet at the traffic ramp, so `deploy-client.yml` cannot reach them before that.

A re-created VM has new addresses. Render the upstream map again (step 5), encrypt it (step 6), and run `play-vultr--nginx.yml -e variable_host=<tier>_pxy`. A re-created proxy VM needs only the play.

Each Vultr host sends its own metrics. Fluent Bit reads the node exporter on the VPC address and sends the metrics to `fluent_bit_vlagent_host`. The base play installs this, so a rebuilt VM needs no render for monitoring. To change only the Fluent Bit config, run `play-vultr--fluent-bit.yml -e variable_host=<group>`. The o11y nodes do not send metrics this way (`fluent_bit_push_metrics: false`), because the cluster scrapes them.

### Private network input

The VPC range and the metrics receiver address are not in this repository. `provider_vultr.yml` reads both from the 1Password item `ops-vultr-private-network` in the vault `Infra-IaC-ESO`. The field `vpc_cidr` holds the private range in CIDR form and gives `vultr_vpc_cidr`. The field `vlagent_host` holds the IPv4 address of the receiver and gives `fluent_bit_vlagent_host`. A play that reads either variable on a Vultr host needs `op` signed in to `freecodecamp.1password.com`. The CI tests give `vultr_vpc_cidr` with `-e` and need no `op`.

### Sender token

Fluent Bit sends logs and metrics to vmauth on port 30427 with a bearer token. vmauth is the only intake on the cluster nodes, so the role refuses a host without the token. The token is the field `credential` of the 1Password item `o11y-fluent-bit-sender` in the vault `Infra-IaC-ESO`. Make it from letters and digits only. All hosts use the same token. The cluster reads the same item through External Secrets. `play-vultr--fluent-bit.yml` and `play-vultr--base.yml` read it with `op`, so sign in to `freecodecamp.1password.com` before you run them. vmauth refuses a wrong token with `401`. Fluent Bit then keeps the metrics and sends them again, but it does not send the logs again. It keeps a copy in `/var/lib/fluent-bit/storage/rejected`, but it does not send that copy. Thus, do not change the token in place. vmauth gets the new token up to about 1 hour later, and then it refuses the logs of each host until the play runs on that host.

If a host gets `401` from vmauth:

1. Make sure that the ExternalSecret `vmauth-fluent-bit-sender` shows `SecretSynced` and the VMUser `fluent-bit-sender` shows `operational`.
2. Run `play-vultr--fluent-bit.yml` on that host with `-e variable_host=<host>`. Make sure that its Fluent Bit log shows no new `401`.

If `op` fails during `play-vultr--base.yml`, the play stops before the later roles. Run the base play again on that host.

The play runs on one host at a time. To do more hosts at a time, add `-e variable_serial=<n>`.

Fluent Bit does not send its own `info` journal lines to VictoriaLogs. Its warnings and errors go there. To see all its lines, run `journalctl -u fluent-bit` on the host.

### Serve the o11y Web UIs on the Tailnet

The list `o11y_tailnet_services` in `inventory/group_vars/ops_o11y_vultr.yml` names each Tailscale Service and its Kubernetes Service. To add a web UI, add it to the list and do these steps for the new Service only.

1. Define the Service once. In the Tailscale admin console, open **Services**, select **Advertise**, then **Define a Service**. Set the name (for example `argocd-o11y`), the endpoint `tcp:443` and the tag `tag:services`.
2. Run the play:

   ```bash
   ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml play-vultr--o11y-tailnet-services.yml -e variable_host=ops_o11y_vultr
   ```

3. In **Services**, select the Service and **Approve** the three o11y nodes.
4. Open the health page. `https://grafana.<tailnet>.ts.net/api/health` sends `"database": "ok"`. `https://argocd-o11y.<tailnet>.ts.net/healthz` sends `ok`.

The play reads the ClusterIP of each Kubernetes Service from the cluster, and uses it as the target. A Service keeps its ClusterIP when Argo CD changes it. If Argo CD creates the Service again, the ClusterIP can change, and the play stops because the node serves the old target. Then run `tailscale serve clear <svc:name>` on each node, and run the play again.

## Removed Plays

| Removed                                                                                                                      | Use instead                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `play-tailscale--1b-up-with-ssh.yml`                                                                                         | `play-tailscale--1a-up.yml -e variable_ssh=true`                                                       |
| `play-k3s--single-node.yml`                                                                                                  | `play-k3s--servers.yml`                                                                                |
| `play-k3s--cluster.yml`                                                                                                      | None. `tools_k3s` has no rebuild play.                                                                 |
| `play-test--1-nginx.yml`                                                                                                     | None.                                                                                                  |
| `play-test--4-…`, `play-test--5-…`, `play-test--6-…`                                                                         | `tests/play-test--4-…`, `tests/play-test--5-…`, `tests/play-test--6-…` (CI runs them)                  |
| `play-any--fix-fstab-swap.yml`                                                                                               | None. The fix ran on every host.                                                                       |
| `play-ghost--0-backup.yml`, `play-oldeworld--ghost-0-initialize.yml`                                                         | None. Ghost is retired.                                                                                |
| `play-o11y--grafana-cloud-0-linuxvm.yml`, `play-o11y--grafana-cloud-1-docker.yml`                                            | None. Alloy is retired.                                                                                |
| `play-o11y--grafana-cloud-9-remove.yml`                                                                                      | None. Alloy is retired.                                                                                |
| `play-o11y--node-exporter-0-install.yml`                                                                                     | `play-vultr--base.yml` installs node_exporter.                                                         |
| `play-o11y--node-exporter-1-verify.yml`                                                                                      | None. It checks a tailnet bind, and each Vultr host binds its VPC address.                             |
| `play-o11y--node-exporter-9-remove.yml`                                                                                      | None.                                                                                                  |
| `play-test--0-docker-swarm.yml`                                                                                              | None.                                                                                                  |
| `play-k3s--bootstrap.yml`                                                                                                    | `play-k3s--servers.yml`. No cluster runs Cilium.                                                       |
| `play-oldeworld--nginx-0-initialize.yml` to `play-oldeworld--nginx-4-upgrade.yml`, `play-oldeworld--update-nginx-config.yml` | `play-vultr--nginx.yml` on a Vultr proxy. The Linode proxies are destroyed.                            |
| `play-oldeworld--clients-list-releases.yml`, `play-oldeworld--clients-restart.yml`, `play-oldeworld--clients-rollback.yml`   | `play-clients--list-releases.yml`, `play-clients--restart.yml`, `play-clients--rollback.yml`           |
| `play-oldeworld--update-client-config.yml`, `play-oldeworld--nodejs-0-update.yml`, `play-oldeworld--pm2-update.yml`          | `play-clients--update-config.yml`, `play-clients--nodejs-0-update.yml`, `play-clients--pm2-update.yml` |

## Former `just` Recipes

Run these from the repository root.

| Recipe                                    | Command                                                                                                                      |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `just bootstrap <play> <group>`           | `cd ansible && ansible-playbook -i inventory/digitalocean.yml play-<play>.yml -e variable_host=<group>`                      |
| `just bootstrap-tools`                    | `cd ansible && uv sync --locked && .venv/bin/ansible-galaxy install -r requirements.yml`                                     |
| `just provision <cmd> <ws>`               | `tofu -chdir=terraform/<ws> <cmd>`. List the workspaces with `find terraform -name .terraform.lock.hcl -exec dirname {} \;`. |
| `just release ops-backoffice-tools <app>` | [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#deployment-pattern)                                                    |
| `just configure-kubeconfig <cluster>`     | See [Kubeconfig From an Envelope](#kubeconfig-from-an-envelope).                                                             |
| `just configure-secret <name>`            | `sops edit --input-type dotenv --output-type dotenv ../infra-secrets/<name>/.env.enc`                                        |
| `just configure-policy <cluster>`         | No replacement. No cluster has a `cluster/policy` folder.                                                                    |
| `just inspect-secret <name>`              | [Runbook 04](../runbooks/04-secrets-decrypt.md)                                                                              |
| `just verify-app <cluster> <app>`         | `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl -n <app> get deploy,sts,pods,svc,secrets -o wide`                         |
| `just inspect-crds <cluster> <filter>`    | `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl get crd \| grep -i <filter>`                                              |
| `just verify-manifests`                   | The `kubeconform` command in `.github/workflows/k8s--validate.yml`                                                           |
| `just verify-secrets`                     | No replacement. Decrypt one envelope with runbook 04 to test the key.                                                        |

## Kubeconfig From an Envelope

Only `ops-backoffice-tools` has a kubeconfig envelope. The `ops-o11y-vultr` kubeconfig comes from `play-k3s--servers.yml`. Run from the repository root:

```bash
(
  umask 077
  f=k3s/<cluster>/.kubeconfig.yaml
  sops decrypt --input-type yaml --output-type yaml \
    ../infra-secrets/k3s/<cluster>/kubeconfig.yaml.enc > "$f.new" &&
    mv "$f.new" "$f" || { rm -f "$f.new"; false; }
)
```

If the decrypt fails, the current kubeconfig stays as it is. The new file has mode `600`.

## Housekeeping Workflow

`ansible--housekeeping.yml` runs in this order: the maintenance window check, uptime, update staging, reboot staging NGINX, check staging NGINX, reboot staging, check the staging Swarm, the same update, reboot and NGINX steps on production, then a last NGINX check and a last Swarm check on staging and production.

- Outside Wednesday and Saturday 00:00-06:00 UTC, the run stops at the window check. Dispatch it with `window_check=false` to run it at another time.
- If the staging NGINX check finds a problem, the production steps do not run that night. This is also true when the restart fixed NGINX.
- The last NGINX check runs on `stg_pxy` and `prd_pxy`, also when the production steps did not run. It can restart NGINX on both groups.
- If the staging Swarm check fails, the production steps do not run that night. It checks each staging `api`, `soc` and `nws` node, and each `stg-` service from the manager.
- The last Swarm check runs on all Swarm nodes and services, also when the production steps did not run.
- The NGINX check posts its findings to Google Chat. The run summary in Google Chat shows each skipped stage. A failed Swarm check shows as a failed stage in that summary, and the job log has the findings.
