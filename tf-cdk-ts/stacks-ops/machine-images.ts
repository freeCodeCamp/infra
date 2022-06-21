import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import { AzurermProvider, ResourceGroup } from '@cdktf/provider-azurerm';

import { StackConfigOptions } from '../components/remote-backend/index';
export default class MachineImagesStack extends TerraformStack {
  constructor(
    scope: Construct,
    tfConstructName: string,
    config: StackConfigOptions
  ) {
    super(scope, tfConstructName);

    const { env, name } = config;

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    const rgIdentifier = `${env}-rg-${name}`;
    new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });
  }
}
