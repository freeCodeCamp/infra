# 22 — Roll back the Vultr move, and deploy during a freeze

**Audience:** operator. **Trigger:** a step of a freeze window is not clean, Vultr fails during the 2-day hold, or a fix must ship during a freeze.

This runbook applies until Linode is shut down. Run every command from the repo root unless the step says otherwise.

## Preconditions

- You recorded the old and new value of each deploy-target secret when you set it.
- [20-traffic-rotation.md](20-traffic-rotation.md) is the procedure for each record change.

## Deploy-target secrets

These secrets select the fleet that a deploy reaches. `gh secret set` prompts for the value and hides it.

| App      | Secret                   | Command                                                                                     |
| -------- | ------------------------ | ------------------------------------------------------------------------------------------- |
| api      | `TS_MACHINE_NAME`        | `gh secret set TS_MACHINE_NAME --repo freeCodeCamp/freeCodeCamp --env <env>-api`            |
| client   | `TS_MACHINE_NAME_PREFIX` | `gh secret set TS_MACHINE_NAME_PREFIX --repo freeCodeCamp/freeCodeCamp --env <env>-clients` |
| socrates | `WEBHOOK_HOST`           | `gh secret set WEBHOOK_HOST --repo freeCodeCamp/socrates --env <env>-socrates`              |
| news     | `WEBHOOK_HOST`           | `gh secret set WEBHOOK_HOST --repo freeCodeCamp/news`                                       |

`<env>` is `stg` or `prd`. The news secret is one value for both environments.

## Go back during a freeze

The two fleets run the same versions, so no deploy is necessary.

1. Move the records back one step at a time ([20-traffic-rotation.md](20-traffic-rotation.md), section Go back).
1. Read the alerts and the request errors. Find the cause before you go on.
1. If you stop the move, set each deploy-target secret of that environment back to its Linode value. Then lift the freeze.

## Go back after a freeze lifts

Deploys reached only Vultr after the freeze, so Linode can be behind. Do these steps in this order:

1. Start a new freeze.
1. Set each deploy-target secret of the environment back to its Linode value.
1. Deploy the running versions to Linode. Use the branch of the environment: `prod-current` for production, `prod-staging` for staging.

   ```sh
   gh workflow run deploy-api.yml --repo freeCodeCamp/freeCodeCamp --ref <branch>
   gh workflow run deploy-client.yml --repo freeCodeCamp/freeCodeCamp --ref <branch>
   gh workflow run deploy-api.yml --repo freeCodeCamp/socrates --ref <branch>
   ```

1. Wait until each run ends with success. Examine each with `gh run list --repo <repo> --limit 5`.
1. Move the records back one step at a time ([20-traffic-rotation.md](20-traffic-rotation.md), section Go back).
1. For production, move the `oncall` jobs back. Use the block in section Deployment of [docker-swarm-oncall.md](../infra-guides/docker-swarm-oncall.md), first with the Vultr command with `stack-oncall.vultr.yml`, then with the Linode command.

## Deploy during a freeze

Only the operator deploys during a freeze. First ask: can this wait until the freeze lifts? If it can, do not deploy.

Two runs of the client workflow can make different asset file names, so do not serve one client version from one fleet and a second version from the other. Use one fleet for the client:

| Record step | api or socrates                                                  | client                                                                                                              |
| ----------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `linode`    | Deploy to Linode, then to Vultr, from the same commit            | Deploy to Linode, then to Vultr, from the same commit                                                               |
| `25`, `50`  | Deploy to Linode, then to Vultr, from the same commit            | Move the records to `linode`. Deploy to Linode, then to Vultr, from the same commit. Move the records forward again |
| `100`       | Deploy to Vultr. Linode is now behind: note this for the go-back | Deploy to Vultr. Linode is now behind: note this for the go-back                                                    |

For each fleet:

1. Set the deploy-target secret of the app to the value of that fleet.
1. Run the workflow, and wait until it ends with success. A production run can wait for a required reviewer.
1. Examine the app through the fleet before you continue.

When you finish, set the secret to the value that the window needs at this time.

News needs no second deploy. Gantry moves the same image on both managers.

## Failure modes

- **A workflow run fails on one fleet.** The fleets now differ. For the client, keep the records on the fleet with the good version. For the api, run the workflow again on the failed fleet, or deploy the earlier commit to the other fleet.
- **The Linode values were not recorded.** A secret value is not readable after you set it. Find the Linode manager and client names in the tailnet device list.
