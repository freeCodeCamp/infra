# Ansible Plays

The plays in `ansible/` and the commands that replace the `justfile` (removed 2026-10-14).

## Before You Start

Run the play commands from `ansible/`. Run the former `just` recipes from the repository root. `direnv exec .` loads the Linode and DigitalOcean tokens.

```bash
cd ansible
uv sync --locked
uv run ansible-galaxy install -r requirements.yml
```

Show the groups:

```bash
direnv exec . uv run ansible-inventory -i inventory/linode.yml --graph
direnv exec . uv run ansible-inventory -i inventory/digitalocean.yml --graph
```

## Rules for Every Play

- Give the target group with `-e variable_host=<group>`.
- A group name that does not exist stops the play with `Could not match supplied host pattern`. If you forget `-e variable_host`, the name in the message is `null` (`play-k3s--bootstrap.yml` says `variable_host` is undefined).
- In GitHub Actions, a group with no hosts gives a warning and the play does nothing.
- Most plays that change hosts do one host at a time and stop at the first host that fails. Some take `-e variable_serial=<n>`. These are different:
  - `play-any--cleanup-clients.yml` does all hosts at the same time and does not stop on a failed host.
  - `play-o11y--node-exporter-9-remove.yml` and `play-o11y--grafana-cloud-9-remove.yml` do 25% of the hosts at a time.
  - `play-o11y--node-exporter-0-install.yml` does 1, then 5, then 10 hosts at a time.
  - `play-any--verify-nginx.yml` and the k3s plays do all hosts at the same time.
- Add `--check` to see the changes without making them. `cleanup-clients`, `clients-restart` and `clients-rollback` also take `-e variable_dry_run=true`.
- Each run adds its output to `ansible/.ansible/ansible.log`.

The command form:

```bash
direnv exec . uv run ansible-playbook -i inventory/linode.yml <play> -e variable_host=<group> [-e <input>=<value>]
```

## Linode Plays

| Play                                        | What it does                                                              | Changes hosts | Inputs                                                                                                         |
| ------------------------------------------- | ------------------------------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------------------------- |
| `play-any--uptime.yml`                      | Show the uptime                                                           | No            | —                                                                                                              |
| `play-any--check-disk-space.yml`            | Report disk and inode use                                                 | No            | `variable_disk_threshold`, `variable_inode_threshold`, `variable_disk_fstypes`                                 |
| `play-any--verify-nginx.yml`                | Check that NGINX runs and starts at boot. Restart it once if it is down.  | Restart only  | `variable_nginx_port`                                                                                          |
| `play-any--update.yml`                      | Upgrade the packages                                                      | Yes           | `variable_serial`                                                                                              |
| `play-any--reboot.yml`                      | Reboot when the host needs it, then wait for it                           | Yes           | `variable_force_reboot=true`, `variable_serial`                                                                |
| `play-any--restart-docker.yml`              | Restart Docker, then wait for it                                          | Yes           | `variable_force_restart=true`, `variable_serial`                                                               |
| `play-any--fail2ban.yml`                    | Install and configure fail2ban                                            | Yes           | `variable_serial`                                                                                              |
| `play-any--cleanup-clients.yml`             | Delete old client releases                                                | Yes           | `variable_dry_run`, `variable_serial`, `variable_client_root`                                                  |
| `play-any--cleanup-jms.yml`                 | Clean up the JMS clients                                                  | Yes           | `variable_serial`                                                                                              |
| `play-any--git-patch.yml`                   | Apply a patch to a Git repository on the host                             | Yes           | `variable_patch_file`, `variable_repo_dir` (both required), `variable_followup_script`, `variable_source_envs` |
| `play-oldeworld--clients-list-releases.yml` | List the client releases                                                  | No            | —                                                                                                              |
| `play-oldeworld--clients-restart.yml`       | Restart the PM2 client services                                           | Yes           | `variable_dry_run`                                                                                             |
| `play-oldeworld--clients-rollback.yml`      | Point the clients to an earlier release                                   | Yes           | `variable_client_binaries_id` (required), `variable_dry_run`, `variable_client_root`                           |
| `play-oldeworld--update-client-config.yml`  | Pull the client config repository                                         | Yes           | `variable_clone`, `variable_serial`                                                                            |
| `play-oldeworld--update-nginx-config.yml`   | Pull the NGINX config, test it, then reload one host at a time            | Yes           | `variable_nginx_port`                                                                                          |
| `play-oldeworld--nginx-0-initialize.yml`    | Install NGINX                                                             | Yes           | —                                                                                                              |
| `play-oldeworld--nginx-1-configure.yml`     | Configure NGINX                                                           | Yes           | —                                                                                                              |
| `play-oldeworld--nginx-2-startup.yml`       | Start NGINX                                                               | Yes           | `variable_add_delay`                                                                                           |
| `play-oldeworld--nginx-3-harden-unit.yml`   | Install the NGINX restart policy and enable the unit at boot              | Yes           | —                                                                                                              |
| `play-oldeworld--nodejs-0-update.yml`       | Update Node.js, the global packages and PM2                               | Yes           | `variable_nodejs_version`                                                                                      |
| `play-oldeworld--pm2-update.yml`            | Move PM2 and its unit to the default Node.js                              | Yes           | —                                                                                                              |
| `play-o11y--node-exporter-0-install.yml`    | Install node_exporter in batches of 1, 5, then 10 hosts. A proxy host stops a larger batch. | Yes           | `variable_serial`                                                                                              |
| `play-o11y--node-exporter-1-verify.yml`     | Check that node_exporter listens on the tailnet only                      | No            | `variable_report_path`                                                                                         |
| `play-o11y--node-exporter-9-remove.yml`     | Remove node_exporter                                                      | Yes           | `variable_serial`                                                                                              |
| `play-o11y--grafana-cloud-9-remove.yml`     | Remove Grafana Alloy                                                      | Yes           | `variable_serial`                                                                                              |
| `play-tailscale--0-install.yml`             | Install Tailscale                                                         | Yes           | `variable_serial`                                                                                              |
| `play-tailscale--1a-up.yml`                 | Connect to the tailnet. Keeps the current Tailscale SSH setting and tags. | Yes           | `TAILSCALE_AUTH_KEY` (env, required), `variable_ssh=true\|false`, `variable_tags`                              |
| `play-tailscale--2-add-cert.yml`            | Get the HTTPS certificate for the tailnet name                            | Yes           | `variable_tailnet_dns_name` (required)                                                                         |
| `play-tailscale--9-down.yml`                | Disconnect from the tailnet                                               | Yes           | `variable_serial`                                                                                              |
| `play-test--2-node-version.yml`             | Show the Node.js, npm and PM2 versions                                    | No            | —                                                                                                              |

## DigitalOcean k3s Plays

Use `-i inventory/digitalocean.yml`.

| Play                      | What it does                                                           | Inputs                                                      |
| ------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------- |
| `play-k3s--servers.yml`   | Install or upgrade k3s on `ops_o11y` (runbook 14)                      | —                                                           |
| `play-k3s--bootstrap.yml` | Install k3s and Cilium on a new cluster. The group config must set `cilium_cluster_id`. | `DO_SPACES_ACCESS_KEY`, `DO_SPACES_SECRET_KEY` (env)        |
| `play-k3s--longhorn.yml`  | Install Longhorn on `tools_k3s`                                        | —                                                           |
| `play-k3s--teardown.yml`  | Remove k3s from every host in the group. Takes an etcd snapshot first. | `confirm_teardown=<group>` (required), `skip_snapshot=true` |

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

## Former `just` Recipes

Run these from the repository root.

| Recipe                                    | Command                                                                                                                                                |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `just bootstrap <play> <group>`           | `cd ansible && direnv exec . uv run ansible-playbook -i inventory/digitalocean.yml play-<play>.yml -e variable_host=<group>`                           |
| `just bootstrap-tools`                    | `cd ansible && uv sync --locked && uv run ansible-galaxy install -r requirements.yml`                                                                  |
| `just provision <cmd> <ws>`               | `terraform -chdir=terraform/<ws> <cmd>`. List the workspaces with `find terraform -name .terraform.lock.hcl -exec dirname {} \;`.                      |
| `just release ops-backoffice-tools <app>` | [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#deployment-pattern)                                                                              |
| `just configure-kubeconfig <cluster>`     | `(umask 077 && sops decrypt --input-type yaml --output-type yaml ../infra-secrets/k3s/<cluster>/kubeconfig.yaml.enc > k3s/<cluster>/.kubeconfig.yaml && chmod 600 k3s/<cluster>/.kubeconfig.yaml)` |
| `just configure-secret <name>`            | `sops edit --input-type dotenv --output-type dotenv ../infra-secrets/<name>/.env.enc`                                                                                                                |
| `just configure-policy <cluster>`         | No replacement. No cluster has a `cluster/policy` folder.                                                |
| `just inspect-secret <name>`              | [Runbook 04](../runbooks/04-secrets-decrypt.md)                                                                                                        |
| `just verify-app <cluster> <app>`         | `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl -n <app> get deploy,sts,pods,svc,secrets -o wide`                                                   |
| `just inspect-crds <cluster> <filter>`    | `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl get crd \| grep -i <filter>`                                                                        |
| `just verify-manifests`                   | The `kubeconform` command in `.github/workflows/k8s--validate.yml`                                                                                     |
| `just verify-secrets`                     | No replacement. Decrypt one envelope with runbook 04 to test the key.                                                                                  |

## Housekeeping Workflow

`ansible--housekeeping.yml` runs in this order: the maintenance window check, uptime, update staging, reboot staging NGINX, check staging NGINX, reboot staging, the same steps on production, then a last NGINX check on production.

- Outside Wednesday and Saturday 00:00-06:00 UTC, the run stops at the window check. Dispatch it with `window_check=false` to run it at another time.
- If the staging NGINX check finds a problem, the production steps do not run that night. This is also true when the restart fixed NGINX.
- The last NGINX check runs on production also when the production steps did not run. It can restart NGINX on `prd_oldeworld_pxy`.
- The NGINX check posts its findings to Google Chat. The run summary in Google Chat shows each skipped stage.
