import { Construct } from 'constructs';
import { App, RemoteBackend, TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  MysqlFlexibleServer,
  PrivateDnsZone,
  PrivateDnsZoneVirtualNetworkLink,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import {
  mysql_fs_sku,
  mysql_admin_username,
  mysql_admin_password,
  mysql_fs_backup_retention_days
} from '../config/env';

class PrdMySQLDBStack extends TerraformStack {
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

    // ----------------------------------
    // Private DNS Zone & Link
    // ----------------------------------
    const privatedz = new PrivateDnsZone(this, 'prd-privatedz-mysql-db', {
      name: 'prd-privatedz-mysql-db',
      resourceGroupName: rg.name
    });
    const privatedzvnetlink = new PrivateDnsZoneVirtualNetworkLink(
      this,
      'prd-privatedzvnetlink-mysql-db',
      {
        name: 'prd-privatedzvnetlink-mysql-db',
        resourceGroupName: rg.name,
        privateDnsZoneName: privatedz.name,
        virtualNetworkId: vnet.id
      }
    );

    // ----------------------------------
    // MySQL Flexible Server
    // ----------------------------------
    new MysqlFlexibleServer(this, 'prd-fs-mysql-db', {
      name: 'prd-fs-mysql-db',
      resourceGroupName: rg.name,
      location: rg.location,
      skuName: mysql_fs_sku,
      administratorLogin: mysql_admin_username,
      administratorPassword: mysql_admin_password,
      backupRetentionDays: mysql_fs_backup_retention_days,
      delegatedSubnetId: subnet.id,
      privateDnsZoneId: privatedz.id,

      dependsOn: [privatedzvnetlink]
    });

    // ----------------------------------
    // End
    // ----------------------------------
  }
}

const app = new App();
const stack = new PrdMySQLDBStack(app, 'prd-stack-mysql-db');
new RemoteBackend(stack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: ' prd-tfws-mysql-db'
  }
});

app.synth();
