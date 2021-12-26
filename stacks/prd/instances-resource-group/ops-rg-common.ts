import { Construct } from 'constructs';
import { TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  PrivateDnsZone,
  ResourceGroup,
  SshPublicKey
} from '@cdktf/provider-azurerm';

import { ssh_public_key } from '../../config/env';

export default class opsRGCommonStack extends TerraformStack {
  constructor(scope: Construct, name: string) {
    super(scope, name);

    new AzurermProvider(this, 'azurerm', {
      features: {}
    });

    const rg = new ResourceGroup(this, 'ops-rg-common', {
      name: 'ops-rg-common',
      location: 'eastus'
    });

    new SshPublicKey(this, 'ops-ssh-key-mrugesh', {
      name: 'ops-ssh-key-mrugesh',
      resourceGroupName: rg.name,
      location: rg.location,
      publicKey: ssh_public_key
    });

    new PrivateDnsZone(this, 'ops-private-dns-zone-org', {
      name: 'private.freecodecamp.org',
      resourceGroupName: rg.name
    });

    new PrivateDnsZone(this, 'ops-private-dns-zone-dev', {
      name: 'private.freecodecamp.dev',
      resourceGroupName: rg.name
    });
  }
}
