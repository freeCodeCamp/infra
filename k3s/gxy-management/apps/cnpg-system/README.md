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

Do not go below CloudNativePG 1.29.1. CVE-2026-44477 (CVSS 9.4, GHSA-423p-g724-fr39) let the metrics exporter reach PostgreSQL superuser and OS command execution. It was fixed in 1.29.1 and 1.28.3, and the 1.28 branch is end-of-life.

The operator owns `Cluster` resources in other namespaces. The artemis `Cluster` is declared by the artemis chart, not here.
