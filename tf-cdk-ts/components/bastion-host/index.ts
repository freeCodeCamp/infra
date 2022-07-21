import { Construct } from 'constructs';
import {
  ResourceGroup,
  VirtualNetwork,
  Subnet,
  BastionHost
} from '@cdktf/provider-azurerm';

import { createPublicIp } from '../public-ip';

export const createBastionHost = (
  stack: Construct,
  stackName: string,
  env: string,
  rg: ResourceGroup,
  vnet: VirtualNetwork,
  addressPrefixes: string[] = ['10.0.0.0/26']
) => {
  const bastionSubnetIdentifier = `${env}-bstn-subnet-${stackName}`;
  const azureBastionSubnet = new Subnet(stack, bastionSubnetIdentifier, {
    dependsOn: [rg, vnet],
    name: 'AzureBastionSubnet',
    resourceGroupName: rg.name,
    virtualNetworkName: vnet.name,
    addressPrefixes
  });

  const bastionPublicIP = createPublicIp(stack, {
    stackName,
    vmName: 'bstn',
    rg,
    env,
    createPublicDnsARecord: false
  });

  const bastionIdentifier = `${env}-bstn-${stackName}`;
  return new BastionHost(stack, bastionIdentifier, {
    dependsOn: [bastionPublicIP, azureBastionSubnet],
    name: bastionIdentifier,
    resourceGroupName: rg.name,
    location: rg.location,
    ipConfiguration: {
      name: `ipconfig-${bastionIdentifier}`,
      publicIpAddressId: bastionPublicIP.id,
      subnetId: azureBastionSubnet.id
    }
  });
};
