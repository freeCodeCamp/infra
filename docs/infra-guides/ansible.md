# Ansible Plays

The plays in `ansible/` and the commands that replace the `justfile` (removed 2026-10-14).

## Before You Start

Run the play commands from `ansible/`. Run the former `just` recipes from the repository root. direnv loads the Linode and DigitalOcean tokens and puts `ansible/.venv/bin` on `PATH`, so `ansible-*` commands need no `uv run`.

```bash
cd ansible
uv sync --locked
.venv/bin/ansible-galaxy install -r requirements.yml
```

On a fresh clone, direnv adds `ansible/.venv/bin` to `PATH` only after `uv sync` and the next `cd` into the repository. The first `ansible-galaxy` call uses the full path for this reason.

Each clone and worktree has its own `.venv` and `.ansible/collections`. Run the two install commands again in each new clone or worktree, and after a pull that changes `pyproject.toml`, `uv.lock` or `requirements.yml`. A stale copy fails in the middle of a play, for example with `Failed to import the required Python library (netaddr)`.

Show the groups:

```bash
ansible-inventory -i inventory/linode.yml --graph
ansible-inventory -i inventory/digitalocean.yml --graph
ansible-inventory -i inventory/vultr.yml -i inventory/constructed.yml --graph
```

The Vultr inventory needs `VULTR_API_KEY`. `ansible/.envrc` loads it from `vultr/.env.enc` when that envelope exists and `CLAUDECODE` is not set. With no key, the inventory gives `HTTP Error 401: Unauthorized`. With no key or no `vultr.cloud` collection, the inventory has no hosts, and the play stops with `Could not match supplied host pattern`.

## Rules for Every Play

- Give the target group with `-e variable_host=<group>`. `play-swarm--form.yml` is different: it takes `swarm_manager_group` and `swarm_worker_group`.
- A group name that does not exist stops the play with `Could not match supplied host pattern`. If you forget `-e variable_host`, the name in the message is `null`.
- In GitHub Actions, a group with no hosts gives a warning and the play does nothing. With the `vultr` provider, the run fails on a group with no hosts or a group name that does not exist, because a Vultr group exists only when a host matches it. The `update` and `reboot` workflows take `check: true` to run with `--check`.
- `ansible--housekeeping.yml` and `ansible--cleanup-clients.yml` name a group and a provider on each job leg. An environment moves to Vultr at its traffic cutover, by a change to its legs.
- Most plays that change hosts do one host at a time and stop at the first host that fails. Some take `-e variable_serial=<n>`. These are different:
  - `play-any--cleanup-clients.yml` does all hosts at the same time and does not stop on a failed host.
  - `play-o11y--node-exporter-9-remove.yml` and `play-o11y--grafana-cloud-9-remove.yml` do 25% of the hosts at a time.
  - `play-o11y--node-exporter-0-install.yml` does 1, then 5, then 10 hosts at a time.
  - `play-any--verify-nginx.yml` and the k3s plays do all hosts at the same time.
- Add `--check` to see the changes without making them. `cleanup-clients`, `clients-restart` and `clients-rollback` also take `-e variable_dry_run=true`.
- Each run adds its output to `ansible/.ansible/ansible.log`.

The command form:

```bash
ansible-playbook -i inventory/linode.yml <play> -e variable_host=<group> [-e <input>=<value>]
```

For a Vultr group, use `-i inventory/vultr.yml -i inventory/constructed.yml` in place of `-i inventory/linode.yml`.

## Linode Plays

| Play                                        | What it does                                                                                | Changes hosts | Inputs                                                                                                                      |
| ------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `play-any--uptime.yml`                      | Show the uptime                                                                             | No            | —                                                                                                                           |
| `play-any--check-disk-space.yml`            | Report disk and inode use                                                                   | No            | `variable_disk_threshold`, `variable_inode_threshold`, `variable_disk_fstypes`                                              |
| `play-any--verify-nginx.yml`                | Check that NGINX runs and starts at boot. Restart it once if it is down.                    | Restart only  | `variable_nginx_port`                                                                                                       |
| `play-any--update.yml`                      | Upgrade the packages                                                                        | Yes           | `variable_serial`                                                                                                           |
| `play-any--reboot.yml`                      | Reboot when the host needs it, then wait for it                                             | Yes           | `variable_force_reboot=true`, `variable_serial`                                                                             |
| `play-any--restart-docker.yml`              | Restart Docker, then wait for it                                                            | Yes           | `variable_force_restart=true`, `variable_serial`                                                                            |
| `play-any--fail2ban.yml`                    | Install and configure fail2ban                                                              | Yes           | `variable_serial`                                                                                                           |
| `play-any--cleanup-clients.yml`             | Delete old client releases                                                                  | Yes           | `variable_dry_run`, `variable_serial`, `variable_client_root`                                                               |
| `play-any--cleanup-jms.yml`                 | Clean up the JMS clients                                                                    | Yes           | `variable_serial`                                                                                                           |
| `play-any--git-patch.yml`                   | Apply a patch to a Git repository on the host                                               | Yes           | `variable_patch_file`, `variable_repo_dir` (both required), `variable_followup_script`, `variable_source_envs`              |
| `play-oldeworld--clients-list-releases.yml` | List the client releases                                                                    | No            | —                                                                                                                           |
| `play-oldeworld--clients-restart.yml`       | Restart the PM2 client services                                                             | Yes           | `variable_dry_run`                                                                                                          |
| `play-oldeworld--clients-rollback.yml`      | Point the clients to an earlier release                                                     | Yes           | `variable_client_binaries_id` (required), `variable_dry_run`, `variable_client_root`                                        |
| `play-oldeworld--update-client-config.yml`  | Pull the client config repository                                                           | Yes           | `variable_clone`, `variable_serial`                                                                                         |
| `play-oldeworld--update-nginx-config.yml`   | Pull the NGINX config, test it, then reload one host at a time                              | Yes           | `variable_nginx_port`                                                                                                       |
| `play-oldeworld--nginx-0-initialize.yml`    | Install NGINX                                                                               | Yes           | —                                                                                                                           |
| `play-oldeworld--nginx-1-configure.yml`     | Configure NGINX                                                                             | Yes           | —                                                                                                                           |
| `play-oldeworld--nginx-2-startup.yml`       | Start NGINX                                                                                 | Yes           | `variable_add_delay`                                                                                                        |
| `play-oldeworld--nginx-3-harden-unit.yml`   | Install the NGINX restart policy and enable the unit at boot                                | Yes           | —                                                                                                                           |
| `play-oldeworld--nginx-4-upgrade.yml`       | Drain one host from its NodeBalancers, upgrade NGINX from nginx.org, then return the host   | Yes           | `variable_drain_seconds`; needs `LINODE_API_TOKEN`                                                                          |
| `play-oldeworld--nodejs-0-update.yml`       | Update Node.js, the global packages and PM2                                                 | Yes           | `variable_nodejs_version`                                                                                                   |
| `play-oldeworld--pm2-update.yml`            | Move PM2 and its unit to the default Node.js                                                | Yes           | —                                                                                                                           |
| `play-o11y--node-exporter-0-install.yml`    | Install node_exporter in batches of 1, 5, then 10 hosts. A proxy host stops a larger batch. | Yes           | `variable_serial`                                                                                                           |
| `play-o11y--node-exporter-1-verify.yml`     | Check that node_exporter listens on the tailnet only                                        | No            | `variable_report_path`                                                                                                      |
| `play-o11y--node-exporter-9-remove.yml`     | Remove node_exporter                                                                        | Yes           | `variable_serial`                                                                                                           |
| `play-o11y--grafana-cloud-9-remove.yml`     | Remove Grafana Alloy                                                                        | Yes           | `variable_serial`                                                                                                           |
| `play-tailscale--0-install.yml`             | Install Tailscale                                                                           | Yes           | `variable_serial`                                                                                                           |
| `play-tailscale--1a-up.yml`                 | Connect to the tailnet. Keeps the current Tailscale SSH setting and tags.                   | Yes           | `op` signed in (reads the Tailscale auth key) or `-e tailscale_auth_key=<key>`, `variable_ssh=true\|false`, `variable_tags` |
| `play-tailscale--2-add-cert.yml`            | Get the HTTPS certificate for the tailnet name                                              | Yes           | `variable_tailnet_dns_name` (required)                                                                                      |
| `play-tailscale--9-down.yml`                | Disconnect from the tailnet                                                                 | Yes           | `variable_serial`                                                                                                           |
| `play-test--2-node-version.yml`             | Show the Node.js, npm and PM2 versions                                                      | No            | —                                                                                                                           |

## Swarm Docker Plays

Run these on the Swarm node groups. The role `docker` applies the same guard to Vultr hosts.

| Play                             | What it does                                                                                                                                        | Changes hosts | Inputs                                                                  |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | ----------------------------------------------------------------------- |
| `play-swarm--docker-guard.yml`   | Install the stray overlay device cleanup that runs before Docker starts, and hold the Docker packages. It does not restart Docker.                  | Yes           | `variable_serial`                                                       |
| `play-swarm--verify.yml`         | Check that each node is active with no stray overlay device. Then check the services from the manager.                                              | No            | `variable_service_prefix`, `variable_manager`, `variable_swarm_retries` |
| `play-swarm--upgrade-docker.yml` | Upgrade the held Docker packages on one node at a time, hold them again, and run the same checks after each node. This restarts Docker on the node. | Yes           | `variable_service_prefix`, `variable_manager`, `variable_swarm_retries` |

`play-any--update.yml` does not upgrade held packages. To upgrade Docker, run `play-swarm--upgrade-docker.yml`. Start with a staging group:

```bash
ansible-playbook -i inventory/linode.yml play-swarm--upgrade-docker.yml \
  -e variable_host=stg_oldeworld_jms -e variable_service_prefix=stg-
```

## DigitalOcean k3s Plays

Use `-i inventory/digitalocean.yml`. For the Vultr o11y cluster, run `play-k3s--servers.yml` with `-i inventory/vultr.yml -i inventory/constructed.yml -e variable_host=ops_o11y_vultr`.

| Play                     | What it does                                                           | Inputs                                                      |
| ------------------------ | ---------------------------------------------------------------------- | ----------------------------------------------------------- |
| `play-k3s--servers.yml`  | Install or upgrade k3s on `ops_o11y` (runbook 14)                      | —                                                           |
| `play-k3s--longhorn.yml` | Install Longhorn on `tools_k3s`                                        | —                                                           |
| `play-k3s--teardown.yml` | Remove k3s from every host in the group. Takes an etcd snapshot first. | `confirm_teardown=<group>` (required), `skip_snapshot=true` |

## Vultr Plays

| Play                          | What it does                                                                                                                                                                                                                     | Inputs                                                                                                                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `play-vultr--base.yml`        | Configure the base of a Vultr host, one host at a time. Stop on a host with no internet. Remove ufw. Give `freecodecamp` sudo, Bash and the `docker` group. Install fail2ban, Docker, node exporter and Fluent Bit. Harden sshd. | `variable_host=<group>`, `variable_serial=<n>`. `--tags login_user` runs only the shell and group steps.                                                                                |
| `play-vultr--clients.yml`     | Prepare a client host for `deploy-client.yml`: Node.js, PM2, `serve`, the `client-config` checkout and the PM2 unit. Serves nothing until a deploy. To move Node.js later, run `play-oldeworld--nodejs-0-update.yml`.            | `variable_host=<group>`, `variable_serial=<n>`                                                                                                                                          |
| `play-swarm--form.yml`        | Form the Vultr Swarm and join the workers, then apply the node labels (runbook 18)                                                                                                                                               | `swarm_manager_group=<group>`, `swarm_worker_group=<group>[:<group>…]`, `swarm_rejoin=true` for a worker that is in another Swarm                                                       |
| `play-vultr--render-maps.yml` | Read each VPC address. Write the NGINX upstream map (plain, to encrypt) or the vmagent targets. Stops when a host of the fleet has no address.                                                                                   | `maps_env=stg\|prd\|ops`, `maps_write=upstreams\|scrape` (`ops` takes `scrape` only)                                                                                                    |
| `play-vultr--manager.yml`     | Prepare the Swarm manager for deploys: `age`, the `~/infra` checkout and its `~/docker-swarm-config` link, `~/.docker`, and the `svc:swarm-wh-vultr` Tailscale Service. Stops when the host holds `svc:swarm-wh`.                | `variable_host=ops_swarm_mgr`. Join the tailnet first with `play-tailscale--0-install.yml` and `play-tailscale--1a-up.yml` with `-e variable_tags=tag:added-by-ops,tag:deployment-tgt`. |
| `play-vultr--nginx.yml`       | Install and start NGINX on a Vultr proxy. Write the Origin CA files, the upstream blocks and the probe listener on the VPC address, port 8081.                                                                                   | `variable_host=<group>`. Reads `docker/vultr/pxy-origin-tls.yaml.enc` and `docker/vultr/pxy-upstreams-<tier>.yaml.enc`.                                                                 |

### Configure a Vultr Environment

Run the steps in this order. No step moves traffic. Cloudflare sends traffic to a proxy only after a DNS record names it ([runbook 20](../runbooks/20-traffic-rotation.md)).

1. Run `play-vultr--base.yml` on each host of the environment.
2. Run `play-swarm--form.yml`.
3. Define `svc:swarm-wh-vultr` once. In the Tailscale admin console, open **Services**, select **Advertise**, then **Define a Service**. Set the endpoint `tcp:443` and the tag `tag:services`.
4. Run `play-tailscale--0-install.yml` and `play-tailscale--1a-up.yml` on `ops_swarm_mgr`, then `play-vultr--manager.yml`. In **Services**, select the Service and **Approve** its host.
5. Make the two envelopes of the proxies. Do step 6 for each file.
   - `pxy-origin-tls`: a YAML map `nginx_tls_files`, one key for each file in `/etc/nginx/ssl` (`dhparam.pem`, `freecodecamp.dev.crt`, `freecodecamp.dev.key`, `freecodecamp.org.crt`, `freecodecamp.org.key`). The play refuses a map that lacks a key.
   - `pxy-upstreams-<tier>`: `play-vultr--render-maps.yml -e maps_env=<tier> -e maps_write=upstreams` writes the plaintext file.
6. From `../infra-secrets`, encrypt the file and delete the plaintext:

   ```bash
   sops -e --input-type yaml --output-type yaml docker/vultr/<name>.yaml.plaintext > docker/vultr/<name>.yaml.enc
   rm -P docker/vultr/<name>.yaml.plaintext
   ```

7. Run `play-vultr--nginx.yml -e variable_host=<tier>_pxy`.
8. Run `play-vultr--clients.yml -e variable_host=<tier>_clt`. The client hosts join the tailnet at the traffic ramp, so `deploy-client.yml` cannot reach them before that.

A re-created VM has new addresses. Render the upstream map again, encrypt it, and run `play-vultr--nginx.yml`.

## Removed Plays

| Removed                                                                           | Use instead                                                                           |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `play-tailscale--1b-up-with-ssh.yml`                                              | `play-tailscale--1a-up.yml -e variable_ssh=true`                                      |
| `play-k3s--single-node.yml`                                                       | `play-k3s--servers.yml`                                                               |
| `play-k3s--cluster.yml`                                                           | None. `tools_k3s` has no rebuild play.                                                |
| `play-test--1-nginx.yml`                                                          | None.                                                                                 |
| `play-test--4-…`, `play-test--5-…`, `play-test--6-…`                              | `tests/play-test--4-…`, `tests/play-test--5-…`, `tests/play-test--6-…` (CI runs them) |
| `play-any--fix-fstab-swap.yml`                                                    | None. The fix ran on every host.                                                      |
| `play-ghost--0-backup.yml`, `play-oldeworld--ghost-0-initialize.yml`              | None. Ghost is retired (runbook 17).                                                  |
| `play-o11y--grafana-cloud-0-linuxvm.yml`, `play-o11y--grafana-cloud-1-docker.yml` | None. Alloy is retired. `play-o11y--grafana-cloud-9-remove.yml` removes it.           |
| `play-test--0-docker-swarm.yml`                                                   | None.                                                                                 |
| `play-k3s--bootstrap.yml`                                                         | `play-k3s--servers.yml`. No cluster runs Cilium.                                      |

## Former `just` Recipes

Run these from the repository root.

| Recipe                                    | Command                                                                                                                                                                                                                         |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `just bootstrap <play> <group>`           | `cd ansible && ansible-playbook -i inventory/digitalocean.yml play-<play>.yml -e variable_host=<group>`                                                                                                                         |
| `just bootstrap-tools`                    | `cd ansible && uv sync --locked && .venv/bin/ansible-galaxy install -r requirements.yml`                                                                                                                                        |
| `just provision <cmd> <ws>`               | `terraform -chdir=terraform/<ws> <cmd>`. For `ops-o11y`, run `cd terraform/ops-o11y && terraform <cmd>`, so direnv loads its `.envrc`. List the workspaces with `find terraform -name .terraform.lock.hcl -exec dirname {} \;`. |
| `just release ops-backoffice-tools <app>` | [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#deployment-pattern)                                                                                                                                                       |
| `just configure-kubeconfig <cluster>`     | See [Kubeconfig From an Envelope](#kubeconfig-from-an-envelope).                                                                                                                                                                |
| `just configure-secret <name>`            | `sops edit --input-type dotenv --output-type dotenv ../infra-secrets/<name>/.env.enc`                                                                                                                                           |
| `just configure-policy <cluster>`         | No replacement. No cluster has a `cluster/policy` folder.                                                                                                                                                                       |
| `just inspect-secret <name>`              | [Runbook 04](../runbooks/04-secrets-decrypt.md)                                                                                                                                                                                 |
| `just verify-app <cluster> <app>`         | `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl -n <app> get deploy,sts,pods,svc,secrets -o wide`                                                                                                                            |
| `just inspect-crds <cluster> <filter>`    | `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl get crd \| grep -i <filter>`                                                                                                                                                 |
| `just verify-manifests`                   | The `kubeconform` command in `.github/workflows/k8s--validate.yml`                                                                                                                                                              |
| `just verify-secrets`                     | No replacement. Decrypt one envelope with runbook 04 to test the key.                                                                                                                                                           |

## Kubeconfig From an Envelope

Only `ops-backoffice-tools` has a kubeconfig envelope. The `ops-o11y` kubeconfig comes from `play-k3s--servers.yml`. Run from the repository root:

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
- The last NGINX check runs on `stg_oldeworld_pxy` and `prd_oldeworld_pxy`, also when the production steps did not run. It can restart NGINX on both groups.
- If the staging Swarm check fails, the production steps do not run that night. It checks each staging API and JMS node, and each `stg-` service from the manager.
- The last Swarm check runs on all Swarm nodes and services, also when the production steps did not run.
- The NGINX check posts its findings to Google Chat. The run summary in Google Chat shows each skipped stage. A failed Swarm check shows as a failed stage in that summary, and the job log has the findings.
