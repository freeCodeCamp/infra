import { Construct } from 'constructs';
import {
  ResourceGroup,
  Subnet,
  LinuxVirtualMachine,
  NetworkInterface,
  NetworkSecurityGroup
} from '@cdktf/provider-azurerm';

import { createPublicIp } from '../public-ip';

import { ssh_public_key, custom_data } from '../../config/env';

interface fCCVirtualMachineConfig {
  name: string;
  vmName: string;
  rg: ResourceGroup;
  subnet: Subnet;
  env: string;
  privateIP?: string | undefined;
}

export const createVirtualMachine = (
  stack: Construct,
  config: fCCVirtualMachineConfig,
  allocatePublicIP: boolean = true
) => {
  const { vmName, rg, subnet, env, privateIP: privateIP = undefined } = config;

  const niIdentifier = `${env}-ni-${vmName}`;
  const ni = new NetworkInterface(stack, niIdentifier, {
    name: niIdentifier,
    resourceGroupName: rg.name,
    location: rg.location,
    ipConfiguration: [
      {
        name: `ipconfig-${vmName}`,
        primary: true,
        subnetId: subnet.id,
        privateIpAddressAllocation: privateIP ? 'Static' : 'Dynamic',
        privateIpAddress: privateIP,
        publicIpAddressId: allocatePublicIP
          ? createPublicIp(stack, vmName, rg, env).id
          : ''
      }
    ]
  });

  const nsgIdentifier = `${env}-nsg-${vmName}`;
  new NetworkSecurityGroup(stack, nsgIdentifier, {
    name: nsgIdentifier,
    resourceGroupName: rg.name,
    location: rg.location,
    securityRule: [
      {
        name: 'allow-ssh',
        priority: 100,
        direction: 'Inbound',
        access: 'Allow',
        protocol: 'Tcp',
        sourcePortRange: '*',
        destinationPortRange: '22',
        sourceAddressPrefix: '*',
        destinationAddressPrefix: '*'
      }
    ]
  });

  const vmIdentifier = `${env}-vm-${vmName}`;
  new LinuxVirtualMachine(stack, vmIdentifier, {
    name: vmIdentifier,
    computerName: String(vmIdentifier).replaceAll('-', ''),
    resourceGroupName: rg.name,
    location: rg.location,
    size: 'Standard_B2s',
    adminUsername: 'freecodecamp',
    adminSshKey: [
      {
        username: 'freecodecamp',
        publicKey: ssh_public_key
      }
    ],
    networkInterfaceIds: [ni.id],
    osDisk: {
      name: `${env}-osdisk-${vmName}`,
      caching: 'ReadWrite',
      storageAccountType: 'Standard_LRS'
    },
    sourceImageReference: {
      publisher: 'Canonical',
      offer: 'UbuntuServer',
      sku: '18.04-LTS',
      version: 'latest'
    },
    // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
    customData: custom_data
  });
};
