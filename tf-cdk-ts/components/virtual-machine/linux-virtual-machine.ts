import { Construct } from 'constructs';
import {
  ResourceGroup,
  Subnet,
  LinuxVirtualMachine,
  NetworkInterface,
  NetworkSecurityGroup,
  NetworkInterfaceSecurityGroupAssociation
} from '@cdktf/provider-azurerm';

import { createPublicIp } from '../public-ip';

import { ssh_public_key } from '../../config/env';

interface fCCVirtualMachineConfig {
  stackName: string;
  vmName: string;
  rg: ResourceGroup;
  subnet: Subnet;
  env: string;
  size?: string;
  privateIP?: string;
  customData?: string;
  allocatePublicIP?: boolean;
  createPublicDnsARecord?: boolean;
}

const defaultCustomData = Buffer.from(
  `#cloud-config
users:
  - name: freecodecamp
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_import_id:
      - gh:camperbot
final_message: 'Setup complete'
`
).toString('base64');
export const createLinuxVirtualMachine = (
  stack: Construct,
  config: fCCVirtualMachineConfig
) => {
  const {
    stackName,
    vmName,
    rg,
    subnet,
    env,
    size: size = 'Standard_B2s',
    privateIP: privateIP = undefined,
    customData: customData = defaultCustomData,
    allocatePublicIP = true,
    createPublicDnsARecord = true
  } = config;

  const nsgIdentifier = `${env}-nsg-${vmName}`;
  const nsg = new NetworkSecurityGroup(stack, nsgIdentifier, {
    dependsOn: [rg],
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

  const niIdentifier = `${env}-ni-${vmName}`;
  const ni = new NetworkInterface(stack, niIdentifier, {
    dependsOn: [nsg],
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
          ? createPublicIp(stack, {
              stackName,
              vmName,
              rg,
              env,
              createPublicDnsARecord
            }).id
          : ''
      }
    ]
  });

  // Attach the security group to the network interface
  new NetworkInterfaceSecurityGroupAssociation(stack, `${env}-nsga-${vmName}`, {
    dependsOn: [ni, nsg],
    networkInterfaceId: ni.id,
    networkSecurityGroupId: nsg.id
  });

  const vmIdentifier = `${env}-vm-${vmName}`;
  return new LinuxVirtualMachine(stack, vmIdentifier, {
    dependsOn: [ni, nsg],
    name: vmIdentifier,
    computerName: String(vmIdentifier).replaceAll('-', ''),
    resourceGroupName: rg.name,
    location: rg.location,
    size: size,
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
    customData: customData
  });
};
