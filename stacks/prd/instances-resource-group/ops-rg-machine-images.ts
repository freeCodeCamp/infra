import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import { AzurermProvider, ResourceGroup } from '@cdktf/provider-azurerm';

export default class opsRGMachineImagesStack extends TerraformStack {
  constructor(scope: Construct, name: string) {
    super(scope, name);

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    new ResourceGroup(this, 'ops-rg-machine-images', {
      name: 'ops-rg-machine-images',
      location: 'eastus'
    });
  }
}
