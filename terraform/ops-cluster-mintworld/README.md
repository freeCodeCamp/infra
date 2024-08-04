# Introduction

This is a collection of Terraform workspaces that are designed to be deployed in conjunction with each other. 

- [`network`](./network/): Creates a VPC with 3 public subnets and 3 private subnets. The subnets are spread across 3 Availability Zones in pairs. This configuration allows for the creation of resources in auto scaling groups (for high availability across AZs) and other similar setups using the subnets created here. Furthermore, a network load balancer is mapped to a convenient DNS name, allowing access to the "controlplane" from developer machines connected via Tailscale.

- [`controlplane`](./controlplane/): Establishes a control plane for the cluster. This includes a set of Nomad and Consul servers deployed in auto scaling groups. It also includes an auto scaling group for Tailscale subnet routers, enabling private access to the Nomad and Consul servers.

- [`workers-web`](./workers-web/): Creates a set of Nomad nodes dedicated to running web servers such as Traefik. These nodes are exclusively intended to serve as proxies for all applications in the cluster.

- [`workers-stateless`](./workers-stateless/): Deploys a set of Nomad nodes designed to run stateless applications, such as API servers.

- [`lifecycle-handlers`](./lifecycle-handlers/): Creates a Lambda function that is triggered by the lifecycle of the ASG in the cluster. It is used to handle the creation and termination of the instances.

While the cluster is primarily designed for deployment in a single AWS region, it is possible to deploy worker nodes in other regions if needed.
