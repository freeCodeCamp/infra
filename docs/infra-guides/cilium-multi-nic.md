# Cilium on multi-NIC nodes — MTU + device pinning

Operator-runnable reference for Cilium on Universe galaxies where nodes carry more than one network interface (e.g. `eth0` + `eth1` + `tailscale0`). Promotes operational findings that previously lived only in field-notes (now consolidated under `Universe/.archive/infra/`) into canonical guidance.

> **Read first:** [ADR-009 §Cilium](https://github.com/freeCodeCamp-Universe/Architecture/blob/main/decisions/009-networking-domains.md#cni-cilium-without-cluster-mesh) for the CNI choice rationale; [ADR-001 §Spike topology](https://github.com/freeCodeCamp-Universe/Architecture/blob/main/decisions/001-topology.md) for the 3-node HA layout this guide assumes.

## When this guide applies

All Universe galaxies today: every droplet ships with `eth0` (public), `eth1` (DO VPC), and `tailscale0` (Tailscale interface). Cilium auto- detects every interface unless told otherwise. The two traps below fire only on multi-NIC nodes — single-NIC clusters skip them.

## The MTU pollution trap

The single most-time-consuming pitfall when bringing up a fresh Universe galaxy.

**Cilium auto-detects all NICs and inherits the LOWEST MTU.** On a DO

- Tailscale node the interfaces look like:

| Interface    | MTU  | Notes                      |
| ------------ | ---- | -------------------------- |
| `eth0`       | 1500 | public                     |
| `eth1`       | 1500 | DO VPC (`10.110.0.0/20`)   |
| `tailscale0` | 1280 | wireguard inside Tailscale |

Without `devices` pinning, Cilium picks 1280 for `cilium_vxlan` and all pod veths. Cross-node TCP packets carrying real payload exceed the path MTU and are silently dropped. **ICMP still works** (small packets), which is the trap — `ping` between pods looks healthy, `curl` times out.

### Symptom shape

- `cilium-health status` reports `Endpoints 0/1` reachable to remote nodes.
- `kubectl exec` ICMP pod→pod across nodes: green.
- `kubectl exec` HTTP pod→pod across nodes: times out at the TCP layer.
- etcd peer traffic to `10.110.0.x:2380` times out from the in-process etcd of remote k3s servers; cluster bring-up stalls with node 1 stuck `activating`. This pattern bit Failure 7 (originally misdiagnosed as a `kubeProxyReplacement` ↔ etcd architectural conflict).

### The trap historically

| Date       | Where          | Symptom                                                                                                          | Resolution                                                  |
| ---------- | -------------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| 2026-04-04 | gxy-management | etcd peers `dial tcp 10.110.0.x:2380: i/o timeout`; node 1 k3s stuck `activating`; misdiagnosed as eBPF conflict | Pin `devices: [eth0, eth1]` + `mtu: 1500` in Cilium values. |
| 2026-04-05 | gxy-management | Cilium health 1/3 reachable; HTTP between pods times out; ICMP healthy                                           | Same pin.                                                   |
| 2026-04-20 | gxy-launchbase | Cluster bring-up — pin applied as standard from values.yaml, no incident                                         | (regression check during bootstrap)                         |
| 2026-04-20 | gxy-cassiopeia | Same — clean bring-up                                                                                            |                                                             |

The 2026-04-04/05 lessons reached `Cilium values.yaml` (in-code) but the WHY only landed in archived field-notes. This guide closes that gap.

## The DO VPC native-routing trap

DigitalOcean's hypervisor-level anti-spoofing **drops packets whose source IP is outside the assigned VPC CIDR**. In Cilium's `tunnel: disabled` (native-routing) mode, cross-node pod traffic carries the pod's pod-CIDR source IP (`10.1.x.x`), which the hypervisor sees as spoofed and drops.

**Resolution.** Use VXLAN tunnel mode on DO VPC — Cilium encapsulates pod traffic with node VPC IPs as the outer source. All Universe galaxies run VXLAN.

## Canonical pattern

Pin `devices`, `mtu`, and `routingMode` in the per-galaxy Cilium values file. The contract:

```yaml
# k3s/<galaxy>/cluster/cilium/values.yaml
kubeProxyReplacement: true # full Cilium takeover (no kube-proxy)
devices: [eth0, eth1] # exclude tailscale0 from device list
mtu: 1500 # explicit, NOT the auto-detected min
routingMode: tunnel # VXLAN — required on DO VPC
tunnelProtocol: vxlan
```

**Subtleties:**

- The `mtu: 1500` value may NOT surface in the rendered `cilium-config` ConfigMap. Verify at runtime: `kubectl -n kube-system exec ds/cilium -- ip link | grep -E 'eth0|eth1|cilium_vxlan|tailscale0'` — all cluster-relevant links must report `mtu 1500`. Tailscale stays at `mtu 1280` and is excluded by the `devices` restriction.
- `kubeProxyReplacement: true` is supported on k3s HA with embedded etcd **once devices + MTU are pinned**. The original misdiagnosis (k3s issues [#5857](https://github.com/k3s-io/k3s/issues/5857) / [#7736](https://github.com/k3s-io/k3s/issues/7736)) describes the same symptoms on this topology but the root cause was MTU, not eBPF.
- The bootstrap play installs Cilium **before** waiting for nodes `Ready`. With `flannel-backend: none` (k3s default for this galaxy class), nodes stay `NotReady` until a CNI is installed. Order: install Cilium first, then wait.

## Open trap — pod → nodeVPCIP (Failure 8b)

Direct connections from pods to node VPC IPs (`10.110.0.x:<port>`) return instant `connection refused` on every port on every node. Affected: `metrics-server` scraping kubelet on `:10250`. Unaffected: pod→pod (VXLAN), pod→service (ClusterIP DNAT), pod→Tailscale IP, pod→external, hostNetwork-to-anything.

**Workaround (in code).** Run affected workloads with `hostNetwork: true`. The bootstrap play patches `metrics-server` to hostNetwork with `--secure-port=4443` (avoids the kubelet `:10250` collision).

**Status.** PARKED. Activation trigger: Cilium 1.20+ release with confirmed fix OR cluster-affecting reproduction. See `flight-manuals/gxy-management.md` Open Decisions table.

## Decision rubric

```text
Bringing up a new galaxy on a multi-NIC topology?
  ├─ Yes  → values.yaml MUST pin devices, mtu, routingMode.
  │         Verify rendered ConfigMap + runtime `ip link` post-install.
  └─ No (single-NIC node)  → defaults are fine; this guide skipped.

Adding a new NIC to an existing cluster (e.g. tailscale rollout)?
  └─ Audit values.yaml first. If devices is empty / unset, the new
     NIC's MTU will silently propagate. Pin the device list before
     `tailscale up` on the first node.

Cross-node pod TCP fails but ICMP works?
  └─ MTU pollution suspect. Check `cilium-config` ConfigMap mtu key,
     then runtime `ip link`. Same symptom as Failure 7+8a.

Pods cannot reach node VPC IPs but service IPs work?
  └─ Open Failure 8b. Workaround: hostNetwork on the affected pod.
     Do NOT spend cycles debugging Cilium policies — they're not in
     the path. See Open trap above.
```

## Configured galaxies

| Galaxy           | Cilium values path                              | devices        | mtu  | routingMode |
| ---------------- | ----------------------------------------------- | -------------- | ---- | ----------- |
| `gxy-management` | `k3s/gxy-management/cluster/cilium/values.yaml` | `[eth0, eth1]` | 1500 | tunnel      |
| `gxy-launchbase` | `k3s/gxy-launchbase/cluster/cilium/values.yaml` | `[eth0, eth1]` | 1500 | tunnel      |
| `gxy-cassiopeia` | `k3s/gxy-cassiopeia/cluster/cilium/values.yaml` | `[eth0, eth1]` | 1500 | tunnel      |

`metrics-server` hostNetwork patch is applied by `ansible/play-k3s--bootstrap.yml` Play 5 across all galaxies — Failure 8b workaround stays uniform.

## Cross-refs

- [`docs/infra-guides/cilium-cnp.md`](./cilium-cnp.md) — sibling guide on CiliumNetworkPolicy patterns and the DNS L7 trap.
- ADR-009 §CNI — Cilium choice rationale.
- ADR-001 §Spike topology — 3-node HA + DO VPC layout.
- `docs/flight-manuals/UNIVERSE.md` §4 lifecycle row "Cilium" — reminder that MTU/devices pin must persist across Cilium bumps.
- `Universe/.archive/infra/2026-04-05-deployment-failures.md` — historical record of Failures 7, 8a, 8b.
- Upstream: <https://docs.cilium.io/en/stable/installation/k3s/> + <https://docs.cilium.io/en/stable/network/concepts/routing/>
- k3s issues describing the misdiagnosis trail: [k3s#5857](https://github.com/k3s-io/k3s/issues/5857), [k3s#7736](https://github.com/k3s-io/k3s/issues/7736).
