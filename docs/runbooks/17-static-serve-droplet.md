# 17 — Static serve droplet for `*.freecode.camp`

**Audience:** operator. **Trigger:** first bring-up, or a rebuild of the droplet.

One droplet runs the `caddy-s3` image with Docker. It serves every site in R2 bucket `universe-static-apps-weur` that has a `production` pointer. Cloudflare proxies the traffic and terminates TLS (SSL mode Flexible). The origin is plain HTTP on port 80. Only Cloudflare ranges reach port 80.

Run every command from the repo root.

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
1. Store the Access Key ID, the Secret Access Key and the S3 endpoint (`https://<account-id>.r2.cloudflarestorage.com`) in one 1Password item.

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
CF=$({ curl -s https://www.cloudflare.com/ips-v4; echo; curl -s https://www.cloudflare.com/ips-v6; echo; } | grep . | sed 's/^/address:/' | paste -sd, -)
doctl compute firewall create \
  --name static-serve \
  --tag-names static-serve \
  --inbound-rules "protocol:tcp,ports:22,address:0.0.0.0/0,address:::/0 protocol:tcp,ports:80,$CF" \
  --outbound-rules "protocol:tcp,ports:all,address:0.0.0.0/0,address:::/0 protocol:udp,ports:all,address:0.0.0.0/0,address:::/0 protocol:icmp,address:0.0.0.0/0,address:::/0"
```

SSH stays public and key-only, the same posture as the o11y node.

## 4. Start the service

Wait for cloud-init. The first `ssh` can fail until cloud-init creates the `freecodecamp` user; retry until it connects:

```sh
ssh freecodecamp@"$IP" cloud-init status --wait
```

Write the env file with the values from step 1. Replace each `<…>`:

```sh
ssh freecodecamp@"$IP" 'sudo install -m 0600 -o root -g root /dev/stdin /etc/caddy-s3/r2.env' <<'EOF'
R2_ENDPOINT=<endpoint>
AWS_ACCESS_KEY_ID=<access-key-id>
AWS_SECRET_ACCESS_KEY=<secret-access-key>
EOF
ssh freecodecamp@"$IP" sudo systemctl start caddy-s3
```

**Verify:** `ssh freecodecamp@"$IP" curl -s http://127.0.0.1/healthz` prints `ok`.

## 5. Smoke the sites on the droplet

Port 80 accepts Cloudflare only, so test from the droplet itself:

```sh
ssh freecodecamp@"$IP" 'curl -s -o /dev/null -w "%{http_code}\n" -H "Host: sudoku.freecode.camp" http://127.0.0.1/'
```

Expect `200`. For the full set, pipe one slug per line:

```sh
ssh freecodecamp@"$IP" 'while read s; do printf "%s " "$s"; curl -s -o /dev/null -w "%{http_code}\n" -H "Host: $s.freecode.camp" http://127.0.0.1/; done' < slugs.txt
```

## 6. Cut DNS over

Cloudflare dashboard → zone `freecode.camp` → **DNS**:

1. Edit the `*` record set: delete two of the three A records, set the third to the droplet IPv4 (`$IP`). Keep **Proxied** on.
1. Do the same for the apex `freecode.camp`.
1. Do not touch `uploads` here. It goes with the management cluster.

**Verify:** `curl -s -o /dev/null -w '%{http_code}\n' https://sudoku.freecode.camp/` prints `200`, and `curl -sI https://freecode.camp/` shows `location: https://www.freecodecamp.org/`.

**Rollback:** while gxy-cassiopeia exists, set the `*` and apex A records back to `165.227.149.249`, `46.101.179.141` and `188.166.165.62`.

## 7. Rebuild

Destroy and repeat steps 2–6. The droplet holds no state. Step 3 is not needed when the firewall still exists, because it binds by tag.

## 8. Update the image

1. Get the new digest: `docker buildx imagetools inspect ghcr.io/freecodecamp/caddy-s3:<tag>`.
1. Change the digest in `cloud-init/static-serve.yml` (two places) and commit.
1. On the droplet, edit `/etc/systemd/system/caddy-s3.service` to the same digest, then run `sudo systemctl daemon-reload && sudo systemctl restart caddy-s3`.
