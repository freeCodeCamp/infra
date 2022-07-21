import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import {
  generateNanoid,
  getLatestImage,
  getSSHPublicKeysListArray
} from '../utils';
import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { getCloudInitForNomadClient } from '../config/nomad/cloud-init';
import { StackConfigOptions } from '../components/remote-backend/index';
import { createVirtualMachine } from '../components/virtual-machine';

export default class stgClusterClientStack extends TerraformStack {
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
      addressSpace: ['10.1.0.0/16']
    });

    const subnetIdentifier = `${env}-subnet-${name}`;
    const subnet = new Subnet(this, subnetIdentifier, {
      name: subnetIdentifier,
      resourceGroupName: rg.name,
      virtualNetworkName: vnet.name,
      addressPrefixes: ['10.1.0.0/24']
    });

    const customImageId = getLatestImage('NomadConsul', 'eastus').id;
    const vmTypeTag = `${env}-nomad-client`;
    const customData = getCloudInitForNomadClient();

    const numberofClients = 5;
    for (let index = 0; index < numberofClients; index++) {
      createVirtualMachine(this, {
        stackName: name,
        vmName: `clt-${generateNanoid()}`,
        rg: rg,
        env: env,
        subnet: subnet,
        privateIP: '10.0.0.' + (200 + index),
        sshPublicKeys: getSSHPublicKeysListArray(),
        customImageId,
        vmTypeTag,
        customData
      });
    }

    // End of stack
  }
}
