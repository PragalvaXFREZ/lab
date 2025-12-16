# Kubernetes Service Lab

#### Overview
This directory contains experiments focused purely on Kubernetes Service behavior.  
The goal is to understand service discovery, DNS resolution, traffic exposure, and security boundaries by isolating Services from application complexity.

A single minimal workload is reused while different Service types are applied on top of it.

#### Topics Covered
- ClusterIP and internal-only services  
- NodePort and node-level exposure  
- LoadBalancer services using MetalLB  
- ExternalName services and DNS aliasing  
- Headless services and direct Pod IP discovery  

#### Key Learnings
- Services abstract network access, not Pod lifecycle  
- Exposure depends on Service type, not the application  
- DNS behavior changes significantly across Service types  
- Some Services proxy traffic, others only affect name resolution  

#### Scope
This lab covers all Kubernetes Service types.  
Ingress, Gateway API, and service meshes are intentionally excluded.
