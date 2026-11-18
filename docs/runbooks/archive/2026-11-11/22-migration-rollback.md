# 22 — Roll back the Vultr move, and deploy to both fleets

> **Historical.** Archived 2026-11-11. Linode is shut down.

**Audience:** operator. **Trigger:** a step of a freeze window is not clean, Vultr fails during the 2-day hold, or an app deploy must reach both fleets.

This runbook applies until Linode is shut down. Run every command from the repo root unless the step says otherwise.

## Preconditions

- You recorded the old and new value of each deploy-target secret when you set it.
- The [traffic runbook](https://github.com/freeCodeCamp/terraform-cloudflare/blob/main/cf-origin-records/README.md) in the private repo `freeCodeCamp/terraform-cloudflare` is the procedure for each record change.

## Deploy-target secrets

These secrets select the fleets that a deploy reaches. Target 1 is the secret without a suffix. Target 2 is the secret with `_2`. One run deploys to target 1, then to target 2. When the `_2` secret is not set, the run deploys to target 1 only. `gh secret set` prompts for the value and hides it.

| App      | Target 1                 | Target 2                   | Command                                                                       |
| -------- | ------------------------ | -------------------------- | ----------------------------------------------------------------------------- |
| api      | `TS_MACHINE_NAME`        | `TS_MACHINE_NAME_2`        | `gh secret set <secret> --repo freeCodeCamp/freeCodeCamp --env <env>-api`     |
| client   | `TS_MACHINE_NAME_PREFIX` | `TS_MACHINE_NAME_PREFIX_2` | `gh secret set <secret> --repo freeCodeCamp/freeCodeCamp --env <env>-clients` |
| socrates | `WEBHOOK_HOST`           | `WEBHOOK_HOST_2`           | `gh secret set <secret> --repo freeCodeCamp/socrates --env <env>-socrates`    |
| news     | `WEBHOOK_HOST`           | none                       | `gh secret set WEBHOOK_HOST --repo freeCodeCamp/news`                         |

`<env>` is `stg` or `prd`. The news secret is one value for both environments. To remove target 2, delete its secret: `gh secret delete <secret> --repo <repo> --env <env>-<app>`.

Set a target 2 secret only when its fleet can take the deploy:

- `prd-clients`: only after the Vultr production clients are on the tailnet. Before that, each production client deploy fails its connection check.
- `prd-socrates`: only after the `prd-socrates` stack exists on the Vultr Swarm. The webhook updates a stack. It does not create one.

## How a run treats two targets

- Before it deploys, the run checks the connection to each machine of both targets. If one machine does not answer, the run deploys to no target.
- The client is built once. Both fleets get the same files and the same release name.
- After the check, the run deploys to each target. If one target fails, the run still deploys to the other target, then ends with a failure. The error names the target by its number, `1` or `2`. The logs hide the machine names.

## Go back during a freeze

The two fleets run the same versions, so no deploy is necessary.

1. Move the records back one step at a time ([traffic runbook](https://github.com/freeCodeCamp/terraform-cloudflare/blob/main/cf-origin-records/README.md), section Go back).
1. Read the alerts and the request errors. Find the cause before you go on.
1. If you stop the move, set target 1 of each app of that environment to its Linode value, and delete the `_2` secrets.
1. If you stop the move in production and you turned the `oncall` jobs off on Linode at the start of the freeze, turn them on again. Use the block in section Deployment of [docker-swarm-oncall.md](../../../infra-guides/docker-swarm-oncall.md) with the Linode command, without `stack-oncall.vultr.yml`.
1. If you stop the move, lift the freeze.

## Go back after a freeze lifts

When target 2 named the other fleet for each app, both fleets run the same versions. Do steps 1, 2, 5, 6 and 7 only.

When a deploy reached one fleet only, Linode can be behind. Do these steps in this order:

1. Start a new freeze.
1. Set target 1 of each app of the environment to its Linode value. Delete the `_2` secrets.
1. Deploy the running versions to Linode. Use the branch of the environment: `prod-current` for production, `prod-staging` for staging.

   ```sh
   gh workflow run deploy-api.yml --repo freeCodeCamp/freeCodeCamp --ref <branch>
   gh workflow run deploy-client.yml --repo freeCodeCamp/freeCodeCamp --ref <branch>
   gh workflow run deploy-api.yml --repo freeCodeCamp/socrates --ref <branch>
   ```

1. Wait until each run ends with success. Examine each with `gh run list --repo <repo> --limit 5`.
1. Move the records back one step at a time ([traffic runbook](https://github.com/freeCodeCamp/terraform-cloudflare/blob/main/cf-origin-records/README.md), section Go back).
1. For production, move the `oncall` jobs back. Use the block in section Deployment of [docker-swarm-oncall.md](../../../infra-guides/docker-swarm-oncall.md), first with the Vultr command with `stack-oncall.vultr.yml`, then with the Linode command.
1. If the Ansible workflows of the environment run on Vultr, move them back. Open a PR that reverts the commit that moved them (`git log --oneline -- .github/workflows/ansible--housekeeping.yml`), and merge it after CI passes.

## Deploy to both fleets

Only the operator approves a deploy during a freeze. First ask: can this wait until the freeze lifts? If it can, do not deploy.

1. Make sure that target 1 and target 2 of the app name the two fleets.
1. Run the workflow once, and wait until it ends with success. A run can wait for a required reviewer.
1. Examine the app through each fleet.

News needs no second deploy. Gantry moves the same image on both managers.

## Failure modes

- **The connection check fails.** No fleet changed. Find the machine that does not answer and repair it. If the fleet cannot take deploys now, delete its `_2` secret and run the workflow again.
- **A run fails on one target.** The fleets now differ. Run the workflow again from the same commit. For the client, if the run fails again, keep the records on the fleet with the good version.
- **The Linode values were not recorded.** A secret value is not readable after you set it. Find the Linode manager and client names in the tailnet device list.
