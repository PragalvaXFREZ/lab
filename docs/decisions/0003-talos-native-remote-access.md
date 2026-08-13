# 0003 - Talos-native remote access

- Status: accepted
- Date: 2026-08-13

## Context

Devata is a bare-metal Talos cluster behind CGNAT. The home network has no independent always-on router, server, VM, or hypervisor available to carry a remote-access tunnel. A Kubernetes-hosted tunnel would also disappear during control-plane, CNI, or workload failure, which is when recovery access matters most.

Plain WireGuard cannot accept reliable inbound connections through CGNAT without a public rendezvous point. Adding a hypervisor or utility VM would reverse the deliberate move to bare-metal Talos.

## Decision

Use NetBird Cloud for coordination and relay, with the NetBird client running as a Talos system extension on each physical node. Enroll nodes with one-off setup keys and restrict access through explicit NetBird peer groups and unidirectional policies.

Run NetBird below Kubernetes. Do not deploy it as a DaemonSet, subnet-router pod, or separate LAN VM. Keep the Talos API on TCP 50000 and the Kubernetes API on TCP 6443 reachable only from the administrator workstation group.

Upgrade Talos from v1.11.5 to v1.12.11 before enabling NetBird because v1.11.5 has no NetBird extension artifact. Keep Kubernetes on v1.34.1 during this operating-system change.

## Consequences

- Remote recovery remains available when Kubernetes, the CNI, or GitOps is unhealthy, provided the target Talos node and NetBird control plane remain reachable.
- NetBird Cloud becomes an external coordination and relay dependency. Peer traffic remains encrypted end to end.
- Every Talos image must retain the NetBird extension during future upgrades.
- Setup keys are never committed. One key enrolls one node and is consumed immediately.
- The initial rollout requires three controlled node reboots and an etcd snapshot before upgrading the single control plane.
- The NetBird extension is contributor-tier in the Talos catalog, so upgrades require explicit extension and service verification.
