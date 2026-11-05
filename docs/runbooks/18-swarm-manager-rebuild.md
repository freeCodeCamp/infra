# 18 — Swarm manager rebuild (Vultr)

**Audience:** operator. **Trigger:** the Vultr Swarm manager `ops-vm-swarm-mgr-1` is lost or broken, or you must re-create it from a new image.

The Vultr Swarm has one manager. The manager holds the Raft state of the Swarm. When the manager goes, the Swarm goes with it: the workers cannot elect a new manager, and you cannot deploy. This runbook makes a new Swarm: a new manager, the workers join it again, and you deploy the stacks again.

> **Outage.** Each worker stops its tasks when it leaves the old Swarm. The Vultr services do not run until you deploy the stacks again (step 8). Before you start, move the Cloudflare traffic to the Linode pool while that pool exists.

Run every command from the repo root unless the step says otherwise.

## Preconditions

- Your shell is on the tailnet, and direnv loads `terraform/ops-swarm-vultr/.envrc` and `ansible/.envrc`.
- The workers are in the groups `stg_api`, `stg_soc`, `stg_nws`, `prd_api`, `prd_soc` and `prd_nws`. The proxy and client VMs are not Swarm nodes.

## 1. Find the image

Use the newest complete `img-` snapshot.

```sh
direnv exec terraform/ops-swarm-vultr sh -c 'curl -fsS -H "Authorization: Bearer $VULTR_API_KEY" "https://api.vultr.com/v2/snapshots?per_page=500"' | jq -r '[.snapshots[] | select((.description // "") | startswith("img-")) | select(.status == "complete")] | sort_by(.date_created) | last | "\(.id) \(.description)"'
```

Export the ID that the line prints:

```sh
export SNAPSHOT_ID=<ID>
```

## 2. Check the tailnet delete credentials

The destroy in step 3 deletes the old tailnet device through the Tailscale API (`terraform/modules/vultr-fleet/tailscale-device-delete.sh`). If the old device stays, the new VM joins as `ops-vm-swarm-mgr-1-1` ([kb/1098](https://tailscale.com/kb/1098/machine-names)). The script needs the OAuth client in `vultr/.env.enc`:

```sh
direnv exec terraform/ops-swarm-vultr env | grep -c '^TAILSCALE_DEVICES_OAUTH_CLIENT_'
```

The command must print `2`.

## 3. Re-create the manager

```sh
direnv exec terraform/ops-swarm-vultr tofu -chdir=terraform/ops-swarm-vultr apply -var snapshot_id="$SNAPSHOT_ID" -replace='module.fleet.vultr_instance.this["ops-vm-swarm-mgr-1"]'
```

The plan must show 1 to add and 1 to destroy. Between `Destroying...` and `Destruction complete`, the output shows `(local-exec): tailscale: deleted <node ID> ops-vm-swarm-mgr-1.<tailnet>.ts.net (200)`. If the VM was not on the tailnet, it shows `tailscale: no tag:added-by-ops device for ops-vm-swarm-mgr-1`. Use `-replace`, not `tofu taint`: a tainted resource skips the delete.

Remove the old host key of the manager from your `known_hosts`:

```sh
ssh-keygen -R ops-vm-swarm-mgr-1
```

## 4. Go to `ansible/`

```sh
cd ansible
```

## 5. Join the manager to the tailnet

```sh
ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml play-tailscale--0-install.yml -e variable_host=ops_swarm_mgr
```

```sh
ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml play-tailscale--1a-up.yml -e variable_host=ops_swarm_mgr -e variable_ssh=false -e variable_tags=tag:added-by-ops,tag:deployment-tgt
```

## 6. Form the new Swarm

```sh
ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml play-swarm--form.yml -e swarm_manager_group=ops_swarm_mgr -e swarm_worker_group=stg_api:stg_soc:stg_nws:prd_api:prd_soc:prd_nws -e swarm_rejoin=true
```

The play initialises the Swarm on the new manager. With `swarm_rejoin=true`, each worker that is in the old Swarm leaves it and joins the new one. The play then applies the node labels.

Check that every node is `Ready`:

```sh
ssh freecodecamp@ops-vm-swarm-mgr-1 sudo docker node ls
```

## 7. Prepare the manager for deploys

```sh
ansible-playbook -i inventory/vultr.yml -i inventory/constructed.yml play-vultr--manager.yml -e variable_host=ops_swarm_mgr
```

The play restores the `~/infra` checkout, the `~/docker-swarm-config` link, the Docker client directories and the webhook Service. The manager must be on the tailnet first (step 5).

Go back to the repo root:

```sh
cd ..
```

## 8. Deploy the stacks again

The new Swarm has no stacks and no configs. If your machine has no `vultr` Docker context, create it:

```sh
docker context create vultr --docker host=ssh://freecodecamp@ops-vm-swarm-mgr-1
```

Deploy each stack by its guide. In each guide block, use `--context vultr` in place of `--context backoffice` or `--context <context_name>`. If you do not, the stack deploys to the Linode Swarm.

- `oncall`: [docker-swarm-oncall.md](../infra-guides/docker-swarm-oncall.md), section Deployment.
- `stg-news`, `prd-news`: [docker-swarm-news.md](../infra-guides/docker-swarm-news.md).
- `stg-socrates`, `prd-socrates`: [docker-swarm-socrates.md](../infra-guides/docker-swarm-socrates.md).
- `stg-api`, `prd-api`: in `freeCodeCamp/freeCodeCamp`, run the workflow `deploy-api.yml` for each environment. Its `TS_MACHINE_NAME` secret must name `ops-vm-swarm-mgr-1`.

Check that each service has its replicas:

```sh
ssh freecodecamp@ops-vm-swarm-mgr-1 sudo docker service ls
```

Move the Cloudflare traffic back to the Vultr pool.

## Practise on `tst-vultr`

Run the same steps on the test VMs, with these changes:

- Step 1: use the snapshot of the last `tst-vultr` apply, not the newest one. A different snapshot re-creates every test VM. Read it with `direnv exec terraform/tst-vultr tofu -chdir=terraform/tst-vultr state show 'vultr_instance.tst["tst-vm-mgr-1"]' | grep snapshot_id`.
- Step 3: `direnv exec terraform/tst-vultr tofu -chdir=terraform/tst-vultr apply -var snapshot_id="$SNAPSHOT_ID" -replace='vultr_instance.tst["tst-vm-mgr-1"]'`, then `ssh-keygen -R tst-vm-mgr-1`.
- Steps 2, 5 and 6: `terraform/ops-swarm-vultr` becomes `terraform/tst-vultr`, `ops-vm-swarm-mgr-1` becomes `tst-vm-mgr-1`, `ops_swarm_mgr` becomes `tst_mgr`, and the worker groups become `tst_wkr`.
- Steps 7 and 8: skip them. From the repo root, run `SNAPSHOT_ID="$SNAPSHOT_ID" CONSOLE_LOGIN_OK=yes direnv exec terraform/tst-vultr terraform/tst-vultr/spike-check.sh`.

Record the time from step 3 to the last `Ready` node.

## Failure modes

- **A run of the Swarm play without `swarm_rejoin` stops with "… outside the Swarm on … Re-run with -e swarm_rejoin=true".** A worker is in another Swarm, or a failed join left it `pending` or `error`. Run the same command again with `-e swarm_rejoin=true`. The worker leaves and joins this Swarm.
- **A worker join times out with HTTP 503.** The worker cannot reach the manager on tcp/2377 over the VPC. On the manager, run `ss -Hltn sport = :2377`. From the worker, run `nc -z -w 5 <manager VPC address> 2377`. A host firewall on either VM is the usual cause; the image removes `ufw`.
- **`docker node ls` shows a node twice, one copy `Down`.** That node joined again with a new node ID. Run `ssh freecodecamp@ops-vm-swarm-mgr-1 sudo docker node rm <ID of the Down copy>`.
- **The apply stops with `curl: (22) … error: <code>`, `tailscale: delete … failed: HTTP <code>` or a variable `is not set`.** The VM is not deleted. A `curl: (22)` 401 or a missing variable: the OAuth client in `vultr/.env.enc` is wrong or absent (step 2). A 403 on the delete: the client has no right to delete that device. Fix the cause and run step 3 again.
- **The tailnet name is `ops-vm-swarm-mgr-1-1`.** The old device was still in the tailnet: it did not have the tag `tag:added-by-ops`, or the VM was destroyed without the delete (`tofu taint`, or a delete in the Vultr console). Remove both devices in the Tailscale admin console, then run the second command of step 5 again.
