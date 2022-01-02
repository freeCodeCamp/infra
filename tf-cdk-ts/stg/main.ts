import { Construct } from 'constructs';
import { App, RemoteBackend, TerraformStack } from 'cdktf';

// import * as keys from './config/env';
import {
  AzurermProvider
  // ResourceGroup,
  // Subnet,
  // VirtualNetwork
} from '@cdktf/provider-azurerm';
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

    // const stg_rg = new ResourceGroup(this, 'stg_rg', {
    //   name: 'stg_rg',
    //   location: 'westus'
    // });

    // // ----------------------------------
    // // Virtual Network
    // // ----------------------------------

    // const stg_vnet = new VirtualNetwork(this, 'stg_vnet', {
    //   name: 'stg_vnet',
    //   resourceGroupName: stg_rg.name,
    //   location: 'westus',
    //   addressSpace: ['10.0.0.0/8']
    // });

    // const stg_subnet = new Subnet(this, 'stg_subnet', {
    //   name: 'stg_subnet',
    //   resourceGroupName: stg_rg.name,
    //   virtualNetworkName: stg_vnet.name,
    //   addressPrefixes: ['10.240.0.0/16']
    // });
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
