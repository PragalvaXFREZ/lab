# Cilium

Cilium provides the cluster datapath, kube-proxy replacement, Gateway API implementation, and Hubble observability.

The `devices` selector is restricted to the nodes' physical `enp+` interfaces. Talos-level overlays such as NetBird's `wt0` are not cluster-facing devices and must not participate in Cilium device or MTU detection. This keeps the pod datapath aligned with the physical LAN while NetBird remains available for node recovery access.

After changing device selection, verify that every Cilium agent lists only its physical NIC under `Devices`, reports the physical-network MTU, and that pod egress works over both UDP and TCP.
