import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  PrivateDnsZone,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { languages } from '../config/news';
import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { createMysqlFlexibleServer } from '../components/mysql-flexible-server';
import { StackConfigOptions } from '../components/remote-backend/index';

export default class prdMySQLDBStack extends TerraformStack {
  constructor(
    scope: Construct,
    tfConstructName: string,
    config: StackConfigOptions
  ) {
    super(scope, tfConstructName);

    const { env, name } = config;

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
          name: `${env}-fs-delegation`,
          serviceDelegation: {
            name: 'Microsoft.DBforMySQL/flexibleServers',
            actions: ['Microsoft.Network/virtualNetworks/subnets/join/action']
          }
        }
      ]
    });

    languages
      .filter(language => language !== 'eng')
      .map(language => {
        const prvDNSZone = new PrivateDnsZone(
          this,
          `${env}-prvdnsfsdb-${language}`,
          {
            name: `${language}.prvdnsfsdb.mysql.database.azure.com`,
            resourceGroupName: rg.name
          }
        );
        createMysqlFlexibleServer(this, `${env}-mysql-fs-${language}`, {
          name: `fcc${env}mysqlfs${language}`,
          resourceGroupName: rg.name,
          location: rg.location,
          delegatedSubnetId: subnet.id,
          privateDnsZoneId: prvDNSZone.id,
          skuName: 'GP_Standard_D2ds_v4',
          storage: {
            iops: 1024,
            sizeGb: 64
          }
        });
      });
  }
}
