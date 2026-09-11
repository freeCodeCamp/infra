# cnpg-system

The CloudNativePG operator on `gxy-management`.

Release:

```sh
just release gxy-management cnpg-system
```

The chart is remote. `charts/cloudnative-pg/repo` names the repository and `charts/cloudnative-pg/version` pins the chart version. Raise the pin in `version`, not on the command line.

| chart  | app (operator) |
| ------ | -------------- |
| 0.29.0 | 1.30.0         |

The operator image is pinned by digest in `values.production.yaml`. The chart has no digest key, so the tag carries both parts as `1.30.0@sha256:<digest>`. Raise the digest in the same commit as the chart version, and never separately: the same string renders into `OPERATOR_IMAGE_NAME`, which is the instance manager every `Cluster` pod runs.

**A change to this string rolls every `Cluster` instance, not only the operator.** CloudNativePG compares the running instance manager against `OPERATOR_IMAGE_NAME`, and the comparison is on the image string, not on the digest it resolves to. Adding the digest to a tag that already pointed at the same bytes was therefore a full rolling restart of `artemis-pg`.

Measured on 2026-09-11, going from `1.30.0` to `1.30.0@sha256:a2701eb…`, the same image:

| mark                                      | value  |
| ----------------------------------------- | ------ |
| operator rollout                          | clean, 0 restarts |
| `artemis-pg` primary not ready            | 10:13:19Z to 10:16:04Z, about 165s |
| phase reported                            | `Primary instance is being restarted without a switchover` |
| artemis `relay.run` errors in the window  | 8, all `dial tcp <rw-svc>:5432: connect: operation not permitted` |
| `artemis-pg-lag-watch` job at 10:15:00Z   | failed both attempts, `backoffLimit: 1` |
| instance container restarts               | 0 |
| deploy rows after                         | 325, replication `streaming` at lag 0 |

Treat a release of this chart as a Postgres maintenance window. Announce it, keep it away from 02:00Z and 04:00Z so the backup and the nightly jobs do not collide, and expect one failed `pg-lag-watch` run.

Do not go below CloudNativePG 1.29.1. CVE-2026-44477 (CVSS 9.4, GHSA-423p-g724-fr39) let the metrics exporter reach PostgreSQL superuser and OS command execution. It was fixed in 1.29.1 and 1.28.3, and the 1.28 branch is end-of-life.

The operator owns `Cluster` resources in other namespaces. The artemis `Cluster` is declared by the artemis chart, not here.
