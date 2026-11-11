# Docker Swarm

> Docker stack configs for our Docker swarm clusters

## Usage

The Swarm runs on Vultr. It has one manager, `ops-vm-swarm-mgr-1`. `play-swarm--form.yml` forms the Swarm, joins the workers and applies the node labels. See [Configure a Vultr Environment](ansible.md#configure-a-vultr-environment). To make the Swarm again after a manager loss, see [runbook 18](../runbooks/18-swarm-manager-rebuild.md).

On a new machine, create the Docker context once:

```shell
docker context create vultr --docker host=ssh://freecodecamp@ops-vm-swarm-mgr-1
```

### Deploy Branches

The deploy workflows (`deploy-api.yml` and `deploy-client.yml` in `freeCodeCamp/freeCodeCamp`, `deploy-api.yml` in `freeCodeCamp/socrates`) deploy `prod-current` to production and every other branch to staging. Each GitHub environment accepts only these branches:

| Environment                              | Branches                   |
| ---------------------------------------- | -------------------------- |
| `stg-api`, `stg-clients`, `stg-socrates` | `prod-staging`, `main`     |
| `prd-api`, `prd-socrates`                | `prod-current`             |
| `prd-clients`                            | `prod-current`, `hotfix-*` |

A `hotfix-*` branch cannot deploy to staging. To test a hotfix on staging, merge it to `prod-staging` first. Then merge it to `prod-current` and deploy production.

### Node Labels

The stack files use the node labels in their placement constraints. The play makes the labels from the host name `<env>-vm-<role>-<n>` (`ansible/vars/swarm.yml`).

| Label                                  | Value                                                  |
| -------------------------------------- | ------------------------------------------------------ |
| `env`                                  | `stg`, `prd`, or `ops` on the manager                  |
| `role`                                 | `api`, `soc`, `nws`, or `swarm-mgr` on the manager     |
| `api.enabled`, `api.variant`           | On `api` nodes: `true`, and `dev` (stg) or `org` (prd) |
| `socrates.enabled`, `socrates.variant` | On `soc` nodes: `true`, and `dev` (stg) or `org` (prd) |
| `jms.enabled`, `jms.variant`           | On `nws` nodes: `true`, and `dev` (stg) or `org` (prd) |

Read the labels on the manager:

```shell
ssh freecodecamp@ops-vm-swarm-mgr-1 docker node ls
ssh freecodecamp@ops-vm-swarm-mgr-1 docker node inspect --format '{{json .Spec.Labels}}' <node id>
```

### Deploy the Stacks

- [oncall](docker-swarm-oncall.md#deployment), [News](docker-swarm-news.md) and [Socrates](docker-swarm-socrates.md#deployment): from the CLI.
- [API](docker-swarm-api.md): from the `deploy-api.yml` workflow in `freeCodeCamp/freeCodeCamp`.

## Stray Overlay Device

Symptom: tasks on one node stay `Rejected` with this error, and the service stays below its target:

```text
network sandbox join failed: subnet sandbox join failed for "<subnet>": error creating vxlan interface: file exists
```

Cause: at shutdown, Docker moves each overlay device to the host namespace, then deletes it. If the daemon exits between these two steps, the device stays. The next daemon does not remove it. Upstream issue: [moby#49555](https://github.com/moby/moby/issues/49555).

A stray device on `ingress` shows a different symptom. The tasks stay at their target, and the Docker journal shows `Failed creating ingress network: ... file exists`.

Fix: on the node, find the device and delete it. On a node without the guard below, a Docker restart does not clear the device. Swarm starts the tasks at its next attempt.

```shell
ip -o link show type vxlan
sudo ip link delete <vx-device>
```

Three controls guard against this fault:

- `play-swarm--docker-guard.yml` deletes stray devices each time Docker starts, and holds the Docker packages. See [Ansible Plays](ansible.md#swarm-docker-plays).
- `svc-watchdog-swarm` and `svc-watchdog-vxlan` post to Google Chat. See [Swarm Watchdogs](docker-swarm-oncall.md#swarm-watchdogs).
- The housekeeping workflow checks the staging Swarm before it updates production. See [Housekeeping Workflow](ansible.md#housekeeping-workflow).
