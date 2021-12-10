import { Construct } from 'constructs';
import { App, RemoteBackend, TerraformStack } from 'cdktf';

// import * as keys from './config/env';
import { AzurermProvider, ResourceGroup } from '@cdktf/provider-azurerm';
class StgStack extends TerraformStack {
  constructor(scope: Construct, name: string) {
    super(scope, name);

    // const { ssh_public_key, custom_data } = keys;

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    // ----------------------------------
    // Resource Group
    // ----------------------------------

    new ResourceGroup(this, 'stg_rg', {
      name: 'stg_rg',
      location: 'westus'
    });
  }
}

const app = new App();
const stack = new StgStack(app, 'stg');
new RemoteBackend(stack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'stg_stack_tfws'
  }
});

app.synth();
