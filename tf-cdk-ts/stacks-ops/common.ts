import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  DnsZone,
  PrivateDnsZone,
  ResourceGroup,
  SshPublicKey
} from '@cdktf/provider-azurerm';

import { StackConfigOptions } from '../components/remote-backend/index';
import members from '../scripts/data/github-members.json';

export default class CommonStack extends TerraformStack {
  constructor(
    scope: Construct,
    tfConstructName: string,
    config: StackConfigOptions
  ) {
    super(scope, tfConstructName);

    const { env, name, tlds } = config;

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    const rgIdentifier = `${env}-rg-${name}`;
    const rg = new ResourceGroup(this, rgIdentifier, {
      name: rgIdentifier,
      location: 'eastus'
    });

    // Create SSH keys for all members of the ops team
    members.forEach((member: { username: string; publicKeys: string[] }) => {
      // console.log(`Creating SSH keys for ${member?.username}`);
      member?.publicKeys.forEach((key, index) => {
        // console.log(
        //   `Key ${index + 1}: ${key.slice(0, 20)}...${key.slice(-20)}`
        // );
        const sshPublicKeyIdentifier = `${env}-ssh-key-${member.username}-${
          index + 1
        }`;
        new SshPublicKey(this, sshPublicKeyIdentifier, {
          name: sshPublicKeyIdentifier,
          resourceGroupName: rg.name,
          location: rg.location,
          publicKey: key
        });
      });
    });

    // Create Private DNS Zones for each domain
    tlds?.forEach((tld: string) => {
      new PrivateDnsZone(this, `${env}-prvdns-${tld}`, {
        name: `prvdns.freecodecamp.${tld}`,
        resourceGroupName: rg.name
      });
    });

    // Create Public DNS Zones for each domain
    tlds?.forEach((tld: string) => {
      new DnsZone(this, `${env}-pubdns-${tld}`, {
        name: `pubdns.freecodecamp.${tld}`,
        resourceGroupName: rg.name
      });
    });
  }
}
