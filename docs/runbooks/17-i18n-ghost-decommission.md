# Runbook — Decommission the i18n Ghost instances

**Type:** Ansible + Terraform + `linode-cli`. **Scope:** the 7 production Ghost VMs `prd-vm-oldeworld-nws-{chn,esp,ita,jpn,kor,por,ukr}`, their data volumes, and the managed MySQL `237699`. **Last verified:** 2026-10-06.

The i18n news sites stay live. The JMS stack `prd-news` serves the static pages. R2 serves the images. Ghost is stopped and disabled on all 7 VMs.

## Archive locations

| What                               | Where                                                                |
| ---------------------------------- | -------------------------------------------------------------------- |
| Images (served live)               | R2 bucket `cdn-media-i18n`, prefix `<language>/`                     |
| Content, config, database dump     | S3 `ghost-backup.freecodecamp.org/Linode-Backups/<code>/2026-10-06/` |
| English Ghost (removed 2024-09-03) | S3 `ghost-backup.freecodecamp.org/Linode-Backups-English/`           |

## Order

Do the steps in this order. Do not apply Terraform before step 3 is complete.

The production proxies resolve `nws-<code>.oldeworld.prd.freecodecamp.net` in `/etc/nginx/configs/upstreams.conf`. Terraform deletes these DNS records. If a name does not resolve, `nginx -t` fails with `host not found in upstream`, and NGINX cannot reload or start.

## Steps

Run every command from the `infra` repository root, unless the step says otherwise.

### 1. Stop the i18n news build

The `freeCodeCamp/news` workflow `i18n - Build and Deploy` reads the Ghost Content API. The oncall service `svc-dispatch-news-i18n` starts it every 6 hours. Stop both before you change anything else.

```sh
gh workflow disable deploy-i18n.yml -R freeCodeCamp/news
docker --context backoffice service rm oncall_svc-dispatch-news-i18n
```

**Verify:**

```sh
gh api repos/freeCodeCamp/news/actions/workflows/deploy-i18n.yml --jq .state
docker --context backoffice service ls -q --filter name=oncall_svc-dispatch-news-i18n | wc -l
```

The state must be `disabled_manually`. The count must be `0`. `docker/swarm/stacks/oncall/stack-oncall.yml` no longer has this service, so a later `docker stack deploy` does not create it again.

### 2. Merge the NGINX change

`freeCodeCamp/nginx-config` branch `fix/drop-i18n-ghost` removes the Ghost proxy locations. The R2 image locations stay.

```sh
git -C ../nginx-config push -u origin fix/drop-i18n-ghost
gh pr create -R freeCodeCamp/nginx-config --head fix/drop-i18n-ghost --fill
```

Merge the PR.

### 3. Deploy NGINX — staging first

Staging upstreams already point at `0.0.0.0:32323`. No upstream change is necessary.

```sh
cd ansible
direnv exec . ansible-playbook -i inventory/ play-oldeworld--update-nginx-config.yml -e variable_host=stg_oldeworld_pxy
```

**Verify staging:**

```sh
for u in /espanol/news/ /espanol/news/ghost/ /news/ghost/; do printf '%s ' $u; curl -s -o /dev/null -w '%{http_code}\n' https://www.freecodecamp.dev$u; done
```

`/espanol/news/` must return `200`. The `/ghost/` paths returned `502` before the change and must not return `502` after it.

Then production. The command also points the 7 `news-<code>` upstreams at `0.0.0.0:32323`, so that no upstream depends on a Ghost DNS record:

```sh
direnv exec . ansible-playbook -i inventory/ play-oldeworld--update-nginx-config.yml -e variable_host=prd_oldeworld_pxy \
  -e '{"nginx_upstreams":[{"name":"news-chn","servers":["0.0.0.0:32323"]},{"name":"news-esp","servers":["0.0.0.0:32323"]},{"name":"news-ita","servers":["0.0.0.0:32323"]},{"name":"news-jpn","servers":["0.0.0.0:32323"]},{"name":"news-kor","servers":["0.0.0.0:32323"]},{"name":"news-por","servers":["0.0.0.0:32323"]},{"name":"news-ukr","servers":["0.0.0.0:32323"]}]}'
cd ..
```

**Verify production:**

```sh
for h in 1 2 3; do printf 'pxy-%s ' $h; ssh freecodecamp@prd-vm-oldeworld-pxy-$h 'grep -c "nws-" /etc/nginx/configs/upstreams.conf'; done
for u in /ukrainian/news/ /ukrainian/news/ghost/ /ukrainian/news/content/images/2022/08/3EA908C2-0015-4A75-9FF3-C8741682CAB0.jpeg; do printf '%s ' $u; curl -s -o /dev/null -w '%{http_code}\n' https://www.freecodecamp.org$u; done
```

Each proxy must print `0`. `/ukrainian/news/` and the image must return `200`. The `/ghost/` path must not return `502`.

### 4. Apply Terraform

`main` must contain `91700b1f` (removes the 7 instances) and `b75950e0` (removes the firewall rule for port 32323 and the Ansible group).

```sh
terraform -chdir=terraform/prd-cluster-oldeworld plan
terraform -chdir=terraform/prd-cluster-oldeworld apply
```

The plan must show `0 to add, 1 to change, 49 to destroy`: 7 resources for each of the 7 instances, and the firewall. If the counts are different, stop.

**Verify:**

```sh
linode-cli linodes list --text --format label | grep -c nws
linode-cli volumes list --text --format label | grep -c nws
dig +short nws-chn.oldeworld.prd.freecodecamp.net
for h in 1 2 3; do ssh freecodecamp@prd-vm-oldeworld-pxy-$h 'sudo nginx -t 2>&1 | tail -1'; done
```

The counts must be `0`, `dig` must print nothing, and each `nginx -t` must print `test is successful`.

### 5. Delete the managed MySQL

```sh
linode-cli databases mysql-delete 237699
linode-cli databases mysql-list --text --format id,label
```

The list must not show `237699`.

### 6. Remove the tailnet devices

In the Tailscale admin console, remove the 7 devices `prd-vm-oldeworld-nws-<code>`.

## Restore a Ghost instance

The instances ran Ghost 3.42.9 on MySQL 8.0.

1. Revert `b75950e0` in `infra` and `fix/drop-i18n-ghost` in `nginx-config`. This puts back the firewall rule, the Ansible group and the NGINX locations.
1. Create the VM: remove the `#` from its line in `nws_instances` in `terraform/prd-cluster-oldeworld/main.tf`, then apply.
1. Restore the database from `Linode-Backups/<code>/2026-10-06/database/` into a MySQL 8.0 server.
1. Copy `Linode-Backups/<code>/2026-10-06/content/` to `/datadrive/content` and `config/config.production.json` to `/var/www/ghost/`.
1. Set the database host in `config.production.json`, then start Ghost.
1. Point the `news-<code>` upstream at `nws-<code>.oldeworld.prd.freecodecamp.net:32323` with `play-oldeworld--update-nginx-config.yml` and `-e nginx_upstreams`.
1. Enable `deploy-i18n.yml`, and put `svc-dispatch-news-i18n` back in the oncall stack.
