import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { createMysqlFlexibleServer } from '../../components/mysql-flexible-server';

export default class prdMySQLDBStack extends TerraformStack {
  constructor(scope: Construct, name: string) {
    super(scope, name);

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    // ----------------------------------
    // Resource Group
    // ----------------------------------
    const rg = new ResourceGroup(this, 'prd-rg-mysql-db', {
      name: 'prd-rg-mysql-db',
      location: 'eastus'
    });

    // ----------------------------------
    // Virtual Network
    // ----------------------------------
    const vnet = new VirtualNetwork(this, 'prd-vnet-mysql-db', {
      name: 'prd-vnet-mysql-db',
      resourceGroupName: rg.name,
      location: rg.location,
      addressSpace: ['10.0.0.0/16']
    });

    // ----------------------------------
    // Subnet
    // ----------------------------------
    const subnet = new Subnet(this, 'prd-subnet-mysql-db', {
      name: 'prd-subnet-mysql-db',
      resourceGroupName: rg.name,
      virtualNetworkName: vnet.name,
      addressPrefixes: ['10.0.2.0/24'],
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

    createMysqlFlexibleServer(this, 'prd-fs-mysql-test', {
      name: 'prd-fs-mysql-test',
      resourceGroupName: rg.name,
      location: rg.location,
      delegatedSubnetId: subnet.id
    });
  }
}
