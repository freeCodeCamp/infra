import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import { getLatestImage, getVMList, getSSHPublicKeysListArray } from '../utils';
import { CLUSTER_DATA_CENTER, CLUSTER_CURRENT_VERSION } from './../config/env';
import { createAzureRBACServicePrincipal } from '../config/service_principal';
import { getCloudInitForNomadConsulCluster } from '../config/cloud-init';
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
      location: CLUSTER_DATA_CENTER
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
      const startIndex = new Date().getUTCMonth() + CLUSTER_CURRENT_VERSION; // Add 1 because January is 0.

      const customImageId = getLatestImage('NomadConsul', 'eastus').id;
      const typeTag = `${env}-nomad-server`;
      const serverList = getVMList({
        vmPrefix: 'ldr-',
        typeTag,
        numberOfVMs,
        startIndex
      });

      let availabiltyzone = 0;
      serverList.forEach(({ name: serverName, privateIP }) => {
        availabiltyzone >= 3 ? (availabiltyzone = 1) : (availabiltyzone += 1);
        const customData = getCloudInitForNomadConsulCluster({
          dataCenter: `${env}-dc-${CLUSTER_DATA_CENTER}`,
          serverList,
          privateIP,
          clusterServerAgent: true
        });
        createVirtualMachine(this, {
          allocatePublicIP: true,
          availabiltyzone: numberOfVMs > 1 ? availabiltyzone : 0,
          createBeforeDestroy: true,
          customData,
          customImageId,
          env: env,
          privateIP,
          rg: rg,
          size: 'Standard_B2s',
          sshPublicKeys: getSSHPublicKeysListArray(),
          stackName: name,
          subnet: subnet,
          typeTag,
          vmName: serverName
        });
      });
    }

    // End of stack
  }
}
