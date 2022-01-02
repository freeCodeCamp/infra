import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { createVirtualMachine } from '../components/virtual-machine';
import { createAzureRBACServicePrincipal } from '../config/service_principal';

export default class GitHubRunners extends TerraformStack {
  constructor(scope: Construct, name: string, config: any) {
    super(scope, name);

    const { env } = config;

    const { subscriptionId, tenantId, clientId, clientSecret } =
      createAzureRBACServicePrincipal(this);
    new AzurermProvider(this, 'azurerm', {
      features: {},
      subscriptionId: subscriptionId.stringValue,
      tenantId: tenantId.stringValue,
      clientId: clientId.stringValue,
      clientSecret: clientSecret.stringValue
    });

    const rgIdentifier = `${env}-rg-${name}`;
    const rg = new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus2'
    });

    const vnetIdentifier = `${env}-vnet-${name}`;
    const vnet = new VirtualNetwork(this, vnetIdentifier, {
      name: vnetIdentifier,
      resourceGroupName: rg.name,
      location: rg.location,
      addressSpace: ['172.16.0.0/16']
    });

    const subnetIdentifier = `${env}-subnet-${name}`;
    const subnet = new Subnet(this, subnetIdentifier, {
      name: subnetIdentifier,
      resourceGroupName: rg.name,
      virtualNetworkName: vnet.name,
      addressPrefixes: ['172.16.0.0/24']
    });

    createVirtualMachine(this, {
      stackName: name,
      vmName: 'engnews',
      rg: rg,
      env: env,
      subnet: subnet,
      size: 'Standard_D4s_v3',
      privateIP: '172.16.0.10'
    });
  }
}
