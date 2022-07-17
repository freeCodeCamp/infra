import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import { AzurermProvider, ResourceGroup } from '@cdktf/provider-azurerm';

import { languages } from '../config/news';
import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { createMysqlFlexibleServer } from '../components/mysql-flexible-server';
import { StackConfigOptions } from '../components/remote-backend/index';

export default class stgMySQLDBStack extends TerraformStack {
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

    languages
      .filter(language => language !== 'eng' && language !== 'chn')
      .map(language => {
        createMysqlFlexibleServer(this, `${env}-mysql-fs-${language}`, {
          name: `fcc${env}mysqlfs${language}`,
          resourceGroupName: rg.name,
          location: rg.location,

          // Server configuration
          // $52.04 per month, per instance.
          skuName: 'B_Standard_B2s',
          storage: {
            iops: 360,
            sizeGb: 20
          }
          // Server configuration
        });
      });
  }
}
