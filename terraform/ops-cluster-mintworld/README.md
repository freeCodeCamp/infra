# Introduction

This is a collection of Terraform workspaces that are ideally deployed in conjuction with each other. 

- [`network`](./network/): Creates a VPC, 3 Public subnets and 3 Private subnets. The subnets are spread accross 3 Availabitlity Zones in pairs. This allows creating resources in auto scaling groups (for high availability across AZs), etc. as needed using the subnets created here.

- [`controlplane`](./controlplane/): Creates a control plane for the cluster. This includes a set of Nomad and Consul servers deployed in auto scaling groups.

  It includes an auto scaling group for Tailscale subnet routers for private access to the Nomad and Consul servers. Additionally, there is network load balancer mapped to a convenient DNS name that can be used to access the "controlplane" from developer machines connected via Tailscale.

- [`workers-web`](./workers-web/): Creates a set of Nomad nodes that are used to run web servers like Traefik, etc. These are exclusively supposed to run as proxies for all apps in the cluster.

- [`workers-stateless`](./workers-stateless/): Creates a set of Nomad nodes that are used to run stateless applications like API servers, etc.

The cluster is designed to be deployed in a single AWS region. However it is possible to deploy worker nodes in other regions.
