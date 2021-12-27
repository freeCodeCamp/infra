import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  DnsZone,
  PrivateDnsZone,
  ResourceGroup,
  SshPublicKey
} from '@cdktf/provider-azurerm';

import { ssh_public_key } from '../config/env';

export default class CommonStack extends TerraformStack {
  constructor(scope: Construct, name: string, config: any) {
    super(scope, name);

    const { env } = config;

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    const rgIdentifier = `${env}-rg-${name}`;
    const rg = new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });

    // TODO: Add Dynamic Logic to create and update SSH Public Keys
    const sshPublicKeyIdentifier = `${env}-ssh-key-mrugesh`;
    new SshPublicKey(this, sshPublicKeyIdentifier, {
      name: sshPublicKeyIdentifier,
      resourceGroupName: rg.name,
      location: rg.location,
      publicKey: ssh_public_key
    });

    const { tlds } = config;

    // Create Private DNS Zones for each domain
    tlds.forEach((tld: string) => {
      new PrivateDnsZone(this, `${env}-prvdns-${tld}`, {
        name: `prvdns.freecodecamp.${tld}`,
        resourceGroupName: rg.name
      });
    });

    // Create Public DNS Zones for each domain
    tlds.forEach((tld: string) => {
      new DnsZone(this, `${env}-pubdns-${tld}`, {
        name: `pubdns.freecodecamp.${tld}`,
        resourceGroupName: rg.name
      });
    });
  }
}
