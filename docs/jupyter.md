# BinderHub (or JupyterHub) on AKS with autoscaling

Jupyter notebook deployments are available for provisioning via multiple
distributions. JupyterHub, is a execution environment that can be pre-configured
with tooling to run Jupyter notebooks. BinderHub, is an environment that builds
upon JupyterHub to provide "code repo => execution environment" functionalities.

**Note:**

_These instructions are a modified and concise version of the BinderHub and
JupTerHub docs, you should read those in full before going through these steps._

_The commands are tweaked for our purposes, to use Azure and follow naming
conventions we think are sane._

## Resources (not ordered) & current limitations:

- Helm Chart - we are using `0.11.1` as of these docs.
  <https://jupyterhub.github.io/helm-chart>
- Setting up AKS & JupyterHub
  <https://zero-to-jupyterhub.readthedocs.io/en/stable/index.html>
- Setting up AKS & BinderHub
  <https://binderhub.readthedocs.io/en/latest/index.html#zero-to-binderhub>
- GenericOAuthenticator - OpenID Connect

  We are choosing this over the inbuilt Auth0 (because of this
  [limitation](https://github.com/jupyterhub/oauthenticator/blob/54a6403a7d797dfc894cdc6a69212f72284459f6/oauthenticator/auth0.py#L52-L63)),
  which does not let us use our FQDN.

  <https://zero-to-jupyterhub.readthedocs.io/en/stable/administrator/authentication.html#id1>

## Confirm access to Azure:

```console az login
  az account list --refresh --output table
  az account set --subscription <SUBSCRIPTION_ID
```

## One-time Operation (most likely not needed):

```console
az extension add --name aks-preview
az feature register --name VMSSPreview --namespace Microsoft.ContainerService

az feature list \
  --output table \
  --query  "[?contains(name, 'Microsoft.ContainerService/VMSSPreview')].{Name:name,State:properties.state}
```

## Create AKS cluster with autoscaling

Full guide:
<https://zero-to-jupyterhub.readthedocs.io/en/stable/kubernetes/microsoft/step-zero-azure-autoscale.html>

### Variables:

> **Note:**
>
> 1. Change variables in below commands as needed.
> 2. Keep the naming patterns as below to avoid errors and inconsistencies.

```console
AKS_RESOURCE_GROUP_NAME=prd_rg_jhub
AKS_LOCATION=eastus
AKS_VNET_NAME=prd_vnet_jhub
AKS_SUBNET_NAME=default
AKS_SERVICE_PRINCIPAL_NAME=sp_aks_jhub
AKS_NODE_RESOURCE_GROUP_NAME=prd_rg_jhub_infra
AKS_KUBERNETES_VERSION=1.19.6
```

> **Note:**
>
> Intentional naming deviation, because Azure does not support underscores in
> cluster names.

```console
AKS_CLUSTER_NAME=prd-aks-jhub
```

### Resource Group:

```console
az group create \
  --name=$AKS_RESOURCE_GROUP_NAME \
  --location=$AKS_LOCATION \
  --output table
```

### Virtual Network and Subnet:

```console
az network vnet create \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --name $AKS_VNET_NAME \
    --address-prefixes 10.0.0.0/8 \
    --subnet-name $AKS_SUBNET_NAME \
    --subnet-prefix 10.240.0.0/16 \
    --output table
```

### Service Principals:

Create service principal, and get the app id and password.

```console
VNET_ID=$(az network vnet show \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --name $AKS_VNET_NAME \
    --query id \
    --output tsv)

SUBNET_ID=$(az network vnet subnet show \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --vnet-name $AKS_VNET_NAME \
    --name $AKS_SUBNET_NAME \
    --query id \
    --output tsv)

SP_PASSWD=$(az ad sp create-for-rbac \
    --name $AKS_SERVICE_PRINCIPAL_NAME \
    --role Contributor \
    --scope $VNET_ID \
    --query password \
    --output tsv)

SP_ID=$(az ad sp show \
    --id http://$AKS_SERVICE_PRINCIPAL_NAME \
    --query appId \
    --output tsv)
```

### Cluster:

Check available supported versions of kubernetes

```console
az aks get-versions --location eastus --output table
```

Create the cluster.

Spinning the cluster will take some time, adjust values as needed (ex. VM sizes
and instance count, etc.).

```console
az aks create --name $AKS_CLUSTER_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --node-resource-group $AKS_NODE_RESOURCE_GROUP_NAME \
    --ssh-key-value  ~/.ssh/id_rsa.pub \
    --node-count 3 \
    --node-vm-size Standard_D2s_v3 \
    --enable-vmss \
    --enable-cluster-autoscaler \
    --min-count 3 \
    --max-count 6 \
    --kubernetes-version $AKS_KUBERNETES_VERSION \
    --service-principal $SP_ID \
    --client-secret $SP_PASSWD \
    --dns-service-ip 10.0.0.10 \
    --docker-bridge-address 172.17.0.1/16 \
    --network-plugin azure \
    --network-policy azure \
    --service-cidr 10.0.0.0/16 \
    --vnet-subnet-id $SUBNET_ID \
    --output table
```

Azure will create two resource groups, one that contains the AKS configs and
another that has only the physical resources (nodes, vm scale sets, etc.) being
use by AKS.

This isolation is managed automatically by Azure RM. The name is set by the
`--node-resource-group` flag.

Deleting the AKS resource group will also delete the corresponding node resource
group.

### Configure `kubectl` & do additional nitty-gritty things:

1. Get credentials for `kubectl`

   ```console
   az aks get-credentials \
     --name $AKS_CLUSTER_NAME \
     --resource-group $AKS_RESOURCE_GROUP_NAME \
     --output table
   ```

2. Verify cluster.

   ```console
   kubectl get node
   ```

3. Check status of Microsoft Insights for Autoscaling

   ```console
   az provider register --namespace microsoft.insights
   az provider show -n microsoft.insights --output table
   ```

4. Enable autoscaling and add rules, on the virtual machine scale set.

   On Azure portal, go to the **VMSS** for the nodes (available in node resource
   group defined previously). Open the **Scaling** option and enable "Custom
   autoscale". Add the below metrics based rules. Adjust instance counts if
   needed.

   - Increase the instance count by 1 when the average CPU usage over 10 minutes
     is greater than 70%

   - Decrease the instance count by 1 when the average CPU usage over 10 minutes
     is less than 5%

---

## BinderHub Installation and Configuration

Full guide:
<https://binderhub.readthedocs.io/en/latest/zero-to-binderhub/index.html>

---

## JupyterHub Installation and Configuration

Full guide:
<https://zero-to-jupyterhub.readthedocs.io/en/stable/jupyterhub/installation.html>

### Variables:

> **Notes:**
>
> 1. Change variables in below commands as needed.
> 2. Keep the naming patterns as below to avoid errors and inconsistencies.

```console
RELEASE=jhub
NAMESPACE=jhub
JHUB_HELM_CHART_VERSION=0.11.1
```

### Generate Secrets:

```console
openssl rand -hex 32
```

Use the above secret with the `config.yaml`

### Installation

Install via `helm`:

```console
helm upgrade --cleanup-on-fail \
  --install $RELEASE jupyterhub/jupyterhub \
  --namespace $NAMESPACE \
  --create-namespace \
  --version=$JHUB_HELM_CHART_VERSION\
  --values config.yaml
```

Verify & check details:

```console
kubectl get pod --namespace $NAMESPACE
kubectl get service --namespace $NAMESPACE
```

Example details of a service:

```console
kubectl describe service proxy-public --namespace $NAMESPACE
```

### Upgrades

```console
helm upgrade --cleanup-on-fail \
  $RELEASE jupyterhub/jupyterhub \
  --namespace $NAMESPACE \
  --version=$JHUB_HELM_CHART_VERSION\
  --values config.yaml
```
