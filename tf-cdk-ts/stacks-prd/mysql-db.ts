import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { createMysqlFlexibleServer } from '../components/mysql-flexible-server';

export default class prdMySQLDBStack extends TerraformStack {
  constructor(scope: Construct, name: string, config: any) {
    super(scope, name);

    const { env } = config;

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    const rgIdentifier = `${env}-rg-${name}`;
    const rg = new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });

    const vnetIdentifier = `${env}-vnet-${name}`;
    const vnet = new VirtualNetwork(this, vnetIdentifier, {
      name: vnetIdentifier,
      resourceGroupName: rg.name,
      location: rg.location,
      addressSpace: ['10.0.0.0/16']
    });

    const subnetIdentifier = `${env}-subnet-${name}`;
    const subnet = new Subnet(this, subnetIdentifier, {
      name: subnetIdentifier,
      resourceGroupName: rg.name,
      virtualNetworkName: vnet.name,
      addressPrefixes: ['10.0.1.0/24'],
      serviceEndpoints: ['Microsoft.Storage'],
      delegation: [
        {
          name: `prd-fs-delegation`,
          serviceDelegation: {
            name: 'Microsoft.DBforMySQL/flexibleServers',
            actions: ['Microsoft.Network/virtualNetworks/subnets/join/action']
          }
        }
      ]
    });

    createMysqlFlexibleServer(this, `${env}-fs-mysql-test`, {
      name: `${env}-fs-mysql-test`,
      resourceGroupName: rg.name,
      location: rg.location,
      delegatedSubnetId: subnet.id
    });
  }
}
