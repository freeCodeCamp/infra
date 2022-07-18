import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import { AzurermProvider, ResourceGroup } from '@cdktf/provider-azurerm';

import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { StackConfigOptions } from '../components/remote-backend/index';
export default class MachineImagesStack extends TerraformStack {
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
    new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });
  }
}
