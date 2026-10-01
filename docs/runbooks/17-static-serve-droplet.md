# 17 — Static serve droplet for `*.freecode.camp`

**Audience:** operator. **Trigger:** first bring-up, or a rebuild of the droplet.

One droplet runs the `caddy-s3` image with Docker. It serves every site in R2 bucket `universe-static-apps-weur` that has a `production` pointer. Cloudflare proxies the traffic and terminates TLS (SSL mode Flexible). The origin is plain HTTP on port 80. Only Cloudflare ranges reach port 80.

Run every command from the repo root. This runbook stays in `docs/runbooks/` because the droplet stays live after the Universe docs leave this repo.

## Topology

| Item       | Value                                                                    |
| ---------- | ------------------------------------------------------------------------ |
| Droplet    | `static-serve-fra1-01`, `s-1vcpu-2gb`, `ubuntu-24-04-x64`, fra1          |
| Tag        | `static-serve` (the firewall binds to it)                                |
| Bootstrap  | `cloud-init/static-serve.yml` (Docker, Caddyfile, systemd unit)          |
| Service    | `caddy-s3.service`; it starts only when `/etc/caddy-s3/r2.env` exists    |
| Image      | `ghcr.io/freecodecamp/caddy-s3`, pinned by digest in the cloud-init file |
| R2 access  | read-only token on `universe-static-apps-weur`, kept in 1Password        |
| Health     | `GET /healthz` returns `ok`                                              |
| Apex, www. | 302 to `https://www.freecodecamp.org{uri}`                               |

## 1. Mint the R2 read token

1. Cloudflare dashboard → **R2** → **Manage API tokens** → **Create API token**.
1. Permission: **Object Read only**. Bucket: `universe-static-apps-weur` only.
1. In 1Password vault `infra`, create item `static-serve-r2-read` with fields `access-key-id`, `secret-access-key` and `endpoint` (`https://<account-id>.r2.cloudflarestorage.com`).

Do not put these values in this repo, in `infra-secrets` or in the cloud-init file.

## 2. Create the droplet

```sh
doctl compute droplet create static-serve-fra1-01 \
  --region fra1 \
  --size s-1vcpu-2gb \
  --image ubuntu-24-04-x64 \
  --tag-name static-serve \
  --ssh-keys "$(doctl compute ssh-key list --format ID --no-header | paste -sd, -)" \
  --user-data-file cloud-init/static-serve.yml \
  --wait
```

Record the public IPv4:

```sh
IP=$(doctl compute droplet get static-serve-fra1-01 --format PublicIPv4 --no-header)
```

## 3. Create the firewall

```sh
CF=$({ curl -fsS https://www.cloudflare.com/ips-v4; echo; curl -fsS https://www.cloudflare.com/ips-v6; echo; } | grep . | sed 's/^/address:/' | paste -sd, -)
test -n "$CF" && doctl compute firewall create \
  --name static-serve \
  --tag-names static-serve \
  --inbound-rules "protocol:tcp,ports:22,address:0.0.0.0/0,address:::/0 protocol:tcp,ports:80,$CF" \
  --outbound-rules "protocol:tcp,ports:all,address:0.0.0.0/0,address:::/0 protocol:udp,ports:all,address:0.0.0.0/0,address:::/0 protocol:icmp,address:0.0.0.0/0,address:::/0"
```

SSH stays public and key-only, the same posture as the o11y node.

## 4. Start the service

Wait for cloud-init. Only the SSH keys of GitHub users `camperbot` and `raisedadead` reach the `freecodecamp` user; root login is off, and `--ssh-keys` in step 2 only stops DigitalOcean from setting a root password. The first `ssh` fails until cloud-init creates the user. Cloud-init can also reboot the droplet after package upgrades; after a disconnect, run the command again:

```sh
ssh freecodecamp@"$IP" cloud-init status --wait
```

Write the env file from the 1Password item of step 1. The values do not reach your terminal or shell history:

```sh
ssh freecodecamp@"$IP" 'sudo install -m 0600 -o root -g root /dev/stdin /etc/caddy-s3/r2.env' <<EOF
R2_ENDPOINT=$(op read "op://infra/static-serve-r2-read/endpoint")
AWS_ACCESS_KEY_ID=$(op read "op://infra/static-serve-r2-read/access-key-id")
AWS_SECRET_ACCESS_KEY=$(op read "op://infra/static-serve-r2-read/secret-access-key")
EOF
ssh freecodecamp@"$IP" sudo systemctl start caddy-s3
```

**Verify:** this prints `ok` within 10 seconds:

```sh
ssh freecodecamp@"$IP" 'for i in $(seq 10); do curl -sf http://127.0.0.1/healthz && break; sleep 1; done'
```

## 5. Smoke the sites on the droplet

Port 80 accepts Cloudflare only, so test from the droplet itself:

```sh
ssh freecodecamp@"$IP" 'curl -s -o /dev/null -w "%{http_code}\n" -H "Host: sudoku.freecode.camp" http://127.0.0.1/'
```

Expect `200`.

## 6. Cut DNS over

Cloudflare dashboard → zone `freecode.camp` → **DNS**:

1. Edit the `*` record set: delete two of the three A records, set the third to the droplet IPv4 (`$IP`). Keep **Proxied** on.
1. Do the same for the apex `freecode.camp`.
1. Do not touch `uploads` here. It goes with the management cluster.

**Verify:** `curl -s -o /dev/null -w '%{http_code}\n' https://sudoku.freecode.camp/` prints `200`, and `curl -sI https://freecode.camp/` shows `location: https://www.freecodecamp.org/`.

**Rollback:** while gxy-cassiopeia exists, set the `*` and apex A records back to `165.227.149.249`, `46.101.179.141` and `188.166.165.62`.

## 7. Rebuild

Destroy and repeat steps 2–6. The droplet holds no state. Step 3 is not needed when the firewall still exists, because it binds by tag.

Cloudflare changes its IP ranges rarely. To re-sync the firewall, build `$CF` as in step 3, then run `doctl compute firewall update <firewall-id>` with the same flags as the `create` line.

## 8. Update the image

1. Get the new digest: `docker buildx imagetools inspect ghcr.io/freecodecamp/caddy-s3:<tag>`.
1. Change the digest in `cloud-init/static-serve.yml` (two places) and commit.
1. On the droplet, edit `/etc/systemd/system/caddy-s3.service` to the same digest, then run `sudo systemctl daemon-reload && sudo systemctl restart caddy-s3`.
