import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { getLatestImage, getVMList, getSSHPublicKeysListArray } from '../utils';
import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { getCloudInitForNomadConsulServers } from '../config/cloud-init';
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
      dependsOn: [rg],
      name: vnetIdentifier,
      resourceGroupName: rg.name,
      location: rg.location,
      addressSpace: ['10.0.0.0/8']
    });

    const subnetIdentifier = `${env}-subnet-${name}`;
    const subnet = new Subnet(this, subnetIdentifier, {
      dependsOn: [vnet],
      name: subnetIdentifier,
      resourceGroupName: rg.name,
      virtualNetworkName: vnet.name,
      addressPrefixes: ['10.0.0.0/16']
    });

    const disabled = false; // Change this to quickly delete only the VMs
    if (!disabled) {
      const numberOfVMs = 3;

      // This will cycle the VMs through the year.
      const startIndex = new Date().getUTCMonth() + 1; // Add 1 because January is 0.

      const customImageId = getLatestImage('NomadConsul', 'eastus').id;
      const vmTypeTag = `${env}-nomad-server`;
      const serverList = getVMList({ vmTypeTag, numberOfVMs, startIndex });
      const customData = getCloudInitForNomadConsulServers(serverList);

      serverList.forEach(({ name: serverName, privateIP }) => {
        createVirtualMachine(this, {
          stackName: name,
          vmName: `ldr-${serverName}`,
          rg: rg,
          env: env,
          size: 'Standard_B2s',
          subnet: subnet,
          privateIP,
          sshPublicKeys: getSSHPublicKeysListArray(),
          customImageId,
          customData,
          vmTypeTag,
          allocatePublicIP: true
        });
      });
    }

    // End of stack
  }
}
