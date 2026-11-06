# 20 — Move traffic between Linode and Vultr

**Audience:** operator. **Trigger:** a freeze window starts, a step must change, or a Vultr NGINX VM must get no traffic.

Proxied A records set the share of traffic. Each record gets about the same share, so the record count sets the percentage. OpenTofu holds the records in `terraform/cf-origin-records/`. One word for each environment, in `steps.tf`, selects the records.

| Step     | `www`, `api`, apex, `chinese`, `socrates` | Other production hostnames | Staging hostnames  |
| -------- | ----------------------------------------- | -------------------------- | ------------------ |
| `linode` | 3 Linode                                  | 1 Linode                   | 1 Linode           |
| `25`     | 3 Linode + 1 Vultr                        | 1 Linode                   | no such step       |
| `50`     | 3 Linode + 3 Vultr                        | 1 Linode + 1 Vultr         | 1 Linode + 1 Vultr |
| `100`    | 3 Vultr                                   | 3 Vultr                    | 3 Vultr            |

No health check moves traffic. If a connection fails with a 521, 522, 523, 525 or 526 error, Cloudflare retries one other address. For other failures, change the step.

Run every command from the repo root.

## Preconditions

- `../infra-secrets/cloudflare/.env.enc` holds:
  - `CLOUDFLARE_API_TOKEN`: a token with DNS Edit on both zones and no other permission.
  - `TF_VAR_zone_ids`: `{"stg":"<zone ID>","prd":"<zone ID>"}`.
  - `TF_VAR_linode_origin_ips`: `{"stg":["<address>"],"prd":["<address>","<address>","<address>"]}`. Put first the production address that the one-record hostnames use.
- All deploys are frozen and go through the operator. Vultr runs the versions that Linode runs.
- The fleet of the environment has 3 NGINX VMs in its state.

## First use

Do this once, before the first window. It takes the existing Linode records into the state and moves no traffic.

1. Approve the environment file of the directory, and initialise the directory:

   ```sh
   direnv allow terraform/cf-origin-records
   direnv exec terraform/cf-origin-records tofu -chdir=terraform/cf-origin-records init
   ```

1. Put the import blocks at `terraform/cf-origin-records/imports.tf`. The blocks hold the Cloudflare record IDs, so they are not in this repository, and Git ignores this path. Each block sets `to = cloudflare_dns_record.origin["<host>/linode-<N>"]` and `id = "<zone ID>/<record ID>"`.

1. Plan and apply. The plan must show 27 to import, 1 to add (`terraform_data.guard`), 0 to change and 0 to destroy. If it shows something else, stop.

   ```sh
   direnv exec terraform/cf-origin-records tofu -chdir=terraform/cf-origin-records apply
   ```

1. Delete the import blocks. A later import fails on a record that step `100` removed, and `tofu test` fails while the file exists.

   ```sh
   rm terraform/cf-origin-records/imports.tf
   ```

1. Plan again. It must show `No changes`.

   ```sh
   direnv exec terraform/cf-origin-records tofu -chdir=terraform/cf-origin-records plan
   ```

1. Check that OpenTofu can read the staging fleet state. The plan must show 18 to add and 6 to destroy. Do not apply it.

   ```sh
   direnv exec terraform/cf-origin-records tofu -chdir=terraform/cf-origin-records plan -var stg_step=100
   ```

## Change a step

1. In `terraform/cf-origin-records/steps.tf`, change the `default` of `stg_step` or `prd_step`.
1. Apply. Read the plan at the prompt, and compare it with this table:

   ```sh
   direnv exec terraform/cf-origin-records tofu -chdir=terraform/cf-origin-records apply
   ```

   | Change                     | To add | To destroy |
   | -------------------------- | ------ | ---------- |
   | Staging `linode` → `50`    | 6      | 0          |
   | Staging `50` → `100`       | 12     | 6          |
   | Production `linode` → `25` | 5      | 0          |
   | Production `25` → `50`     | 16     | 0          |
   | Production `50` → `100`    | 12     | 21         |

1. Commit the changed word.
1. Check the step:
   - Read the share of requests for each origin address, with this Cloudflare GraphQL query. The token in `cloudflare/.env.enc` cannot read analytics. Use a session that has Analytics Read.

     ```graphql
     query {
       viewer {
         zones(filter: { zoneTag: "<zone ID>" }) {
           httpRequestsAdaptiveGroups(
             limit: 20
             filter: {
               datetime_geq: "<start>"
               datetime_lt: "<end>"
               originIP_neq: ""
             }
             orderBy: [count_DESC]
           ) {
             count
             dimensions {
               originIP
             }
           }
         }
       }
     }
     ```

   - Read the alerts in the Google Chat space.
   - Read the request errors on the Vultr hosts ([19-o11y-alerts.md](19-o11y-alerts.md)).

Go on to the next step only if the error rate, the alerts and the latency are clean.

## Staging latency gate

The api p95 latency on Vultr must be no more than 150 ms above Linode. Read the value before the window, and again after at least 6 hours at `100`. An earlier read includes samples from step `50`:

```sh
KUBECONFIG=k3s/ops-o11y-vultr/.kubeconfig.yaml kubectl get --raw '/api/v1/namespaces/o11y/services/vmselect-vm:8481/proxy/select/0/prometheus/api/v1/query?query=quantile_over_time(0.95,probe_duration_seconds%7Binstance%3D%22https://api.freecodecamp.dev/status/ping%22%7D%5B6h%5D)'
```

## Go back

Set the word of the step before, and apply. Go back one step at a time. Do not go from `100` directly to `linode`: that apply destroys and creates records in no fixed order, so a hostname can have no record for a short time.

| Change                     | To add | To destroy |
| -------------------------- | ------ | ---------- |
| Staging `100` → `50`       | 6      | 12         |
| Staging `50` → `linode`    | 0      | 6          |
| Production `100` → `50`    | 21     | 12         |
| Production `50` → `25`     | 0      | 16         |
| Production `25` → `linode` | 0      | 5          |

While the Linode records exist, the two fleets run the same versions, so no deploy is necessary.

After the freeze lifts, deploys reach only Vultr. To return to Linode then, first deploy the running versions to Linode.

## A Vultr NGINX VM must get no traffic

1. In `terraform/cf-origin-records/steps.tf`, add the VM name to the `default` of `proxies_down`, such as `["prd-vm-pxy-2"]`.
1. Apply, and commit:

   ```sh
   direnv exec terraform/cf-origin-records tofu -chdir=terraform/cf-origin-records apply
   ```

1. When the VM is good again, remove the name, apply and commit.

## Failure modes

| Symptom                                              | Cause                                                                                                                                     | Fix                                                   |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| The plan stops at `terraform_data.guard`             | The fleet state does not have 3 NGINX VMs, all of them are in `proxies_down`, or `proxies_down` names a VM that is not in the fleet state | Build the VMs, or correct `proxies_down`              |
| The plan after the import does not show `No changes` | A record differs from the configuration                                                                                                   | Stop. Do not apply. Compare the record with `main.tf` |
| The plan cannot read a fleet state                   | The R2 keys or `TF_VAR_state_passphrase` are not loaded, or the fleet is not applied                                                      | Load the envelopes; apply the fleet first             |
