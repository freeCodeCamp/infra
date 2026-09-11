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

Do not go below operator 1.29.1. CVE-2026-44477 (CVSS 9.4) in the metrics exporter was fixed there, and the 1.28 branch is end-of-life.

The operator owns `Cluster` resources in other namespaces. The artemis `Cluster` is declared by the artemis chart, not here.
