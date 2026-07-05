# Kubernetes Scheduling - Deep Dive

A hands-on exploration of Kubernetes scheduling concepts, demonstrating how the kube-scheduler decides pod placement across cluster nodes.

## 📚 Topics Covered

| Concept | Description |
|---------|-------------|
| **Node Affinity** | Control pod placement using node labels with required and preferred rules |
| **Taints & Tolerations** | Restrict which pods can run on specific nodes |
| **Topology Spread Constraints** | Distribute pods evenly across zones/nodes for high availability |
| **Pod Priority & Preemption** | Define scheduling priority to ensure critical workloads get resources first |
| **Resource Quotas** | Set namespace-level limits for CPU, memory, and pod count |
| **Limit Ranges** | Enforce default and max resource constraints at pod/container level |
| **Scheduling Gates** | Hold pods in pending state until external conditions are met |
| **Node Selection** | Direct pod-to-node binding using `nodeName` |

## 🔬 Key Learnings

- Understanding why pods stay in `Pending` state and how to debug scheduling failures
- How affinity rules affect the scheduler's filtering and scoring phases
- Implementing fair resource distribution across namespaces with quotas
- Using priority classes for workload tiering in resource-constrained clusters

## 📝 Related Blog

For a detailed walkthrough of these concepts, check out my article:

**[Why Your Pod is Pending: A Deep Dive into the K8s Scheduler](https://medium.com/@pragalva.sapkota/why-your-pod-is-pending-a-deep-dive-into-the-k8s-scheduler-42e9f608d155)**

---

*Part of my Kubernetes learning journey via [Kubesimplify Bootcamp](https://kubesimplify.com/)*
