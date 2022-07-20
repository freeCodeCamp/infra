import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { custom_data } from '../config/env';
import { fiveLetterNames } from '../config/constant-strings';
import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { getLatestImage, getSSHPublicKeysListArray } from '../utils';
import { StackConfigOptions } from '../components/remote-backend/index';
import { createVirtualMachine } from '../components/virtual-machine';

export default class stgClusterServerStack extends TerraformStack {
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
      addressPrefixes: ['10.0.0.0/24']
    });

    const numberofServers = 3;
    const nomadServerNames = fiveLetterNames.slice(0, numberofServers);

    const customImage = getLatestImage('NomadConsul', 'eastus');
    nomadServerNames.map((serverName, index) => {
      createVirtualMachine(this, {
        stackName: name,
        vmName: `ldr-${serverName}`,
        rg: rg,
        env: env,
        size: 'Standard_D2s_v4',
        subnet: subnet,
        privateIP: '10.0.0.' + (10 + index),
        sshPublicKeys: getSSHPublicKeysListArray(),
        customImageId: customImage.id,
        customData: custom_data
      });
    });

    // End of stack
  }
}
