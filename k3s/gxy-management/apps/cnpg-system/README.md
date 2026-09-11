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

A release restarts the operator pod. Running `Cluster` instances keep serving while the operator is down, so this needs no window, but do not release it during a failover.

Do not go below CloudNativePG 1.29.1. CVE-2026-44477 (CVSS 9.4, GHSA-423p-g724-fr39) let the metrics exporter reach PostgreSQL superuser and OS command execution. It was fixed in 1.29.1 and 1.28.3, and the 1.28 branch is end-of-life.

The operator owns `Cluster` resources in other namespaces. The artemis `Cluster` is declared by the artemis chart, not here.
