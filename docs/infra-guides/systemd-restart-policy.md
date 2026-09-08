# systemd restart policy

Every unit that Ansible manages bounds its restarts. A real fault must end in a
visible `failed` state, not in an endless restart loop. `Restart=on-failure`
covers a transient fault. `StartLimitIntervalSec` and `StartLimitBurst` stop
the loop when the fault does not clear.

Size the bound to the start cycle of the unit. The bound must permit enough
attempts to ride out a slow dependency, and it must trip well inside the time
an operator can wait for a clear signal.

| Unit            | Start cycle                                   | Bound                                 | Applied by                                               |
| --------------- | --------------------------------------------- | ------------------------------------- | -------------------------------------------------------- |
| `nginx`         | `RestartSec=20s`, no start gate               | 10 attempts in 600 s, about 3 minutes | `roles/nginx/tasks/harden-unit.yml`                      |
| `node_exporter` | `tailscale wait` up to 60 s, `RestartSec=15s` | 5 attempts in 600 s, about 6 minutes  | `roles/node-exporter/templates/node_exporter.service.j2` |

A tripped bound stays tripped until `systemctl reset-failed <unit>`, a manual
`systemctl restart <unit>`, or a reboot. The verify plays report a `failed`
unit as a finding, so the failed state is the signal, not a silent gap.
