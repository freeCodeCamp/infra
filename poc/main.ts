import { Construct } from 'constructs';
import { App, RemoteBackend, TerraformStack } from 'cdktf';
import {
  AzurermProvider,
  Lb,
  LbBackendAddressPool,
  LbProbe,
  LbRule,
  LinuxVirtualMachine,
  NetworkInterface,
  NetworkInterfaceBackendAddressPoolAssociation,
  NetworkSecurityGroup,
  NetworkSecurityRule,
  PublicIp,
  ResourceGroup,
  Subnet,
  VirtualNetwork
} from '@cdktf/provider-azurerm';

import * as keys from './config/env';
class StagingStack extends TerraformStack {
  constructor(scope: Construct, name: string, keys: any) {
    super(scope, name);

    const { ssh_public_key, custom_data } = keys;

    new AzurermProvider(this, 'azurerm', {
      features: [{}]
    });

    // ----------------------------------
    // Resource Group
    // ----------------------------------

    const stg_rg = new ResourceGroup(this, 'stg_rg', {
      name: 'stg_rg',
      location: 'westus'
    });

    // ----------------------------------
    // Virtual Network
    // ----------------------------------

    const stg_vnet = new VirtualNetwork(this, 'stg_vnet', {
      name: 'stg_vnet',
      resourceGroupName: stg_rg.name,
      location: 'westus',
      addressSpace: ['10.0.0.0/8']
    });

    const stg_subnet = new Subnet(this, 'stg_subnet', {
      name: 'stg_subnet',
      resourceGroupName: stg_rg.name,
      virtualNetworkName: stg_vnet.name,
      addressPrefixes: ['10.240.0.0/16']
    });

    // ----------------------------------
    // Public IP Addresses
    // ----------------------------------

    // Public IP Address for the LoadBalancer (external)
    const stg_public_ip_lb = new PublicIp(this, 'stg_public_ip_lb', {
      name: 'stg_public_ip_lb',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    const stg_public_ip_web = new PublicIp(this, 'stg_public_ip_web', {
      name: 'stg_public_ip_web',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    const stg_public_ip_api_alpha = new PublicIp(
      this,
      'stg_public_ip_api_alpha',
      {
        name: 'stg_public_ip_api_alpha',
        resourceGroupName: stg_rg.name,
        location: stg_rg.location,
        allocationMethod: 'Static',
        sku: 'Basic'
      }
    );

    const stg_public_ip_api_bravo = new PublicIp(
      this,
      'stg_public_ip_api_bravo',
      {
        name: 'stg_public_ip_api_bravo',
        resourceGroupName: stg_rg.name,
        location: stg_rg.location,
        allocationMethod: 'Static',
        sku: 'Basic'
      }
    );

    const stg_public_ip_clt_eng = new PublicIp(this, 'stg_public_ip_clt_eng', {
      name: 'stg_public_ip_clt_eng',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    const stg_public_ip_clt_chn = new PublicIp(this, 'stg_public_ip_clt_chn', {
      name: 'stg_public_ip_clt_chn',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    const stg_public_ip_clt_esp = new PublicIp(this, 'stg_public_ip_clt_esp', {
      name: 'stg_public_ip_clt_esp',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    const stg_public_ip_clt_cnt = new PublicIp(this, 'stg_public_ip_clt_cnt', {
      name: 'stg_public_ip_clt_cnt',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    const stg_public_ip_clt_ita = new PublicIp(this, 'stg_public_ip_clt_ita', {
      name: 'stg_public_ip_clt_ita',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    const stg_public_ip_clt_por = new PublicIp(this, 'stg_public_ip_clt_por', {
      name: 'stg_public_ip_clt_por',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      allocationMethod: 'Static',
      sku: 'Basic'
    });

    // ----------------------------------
    // Load Balancer - Web Proxy Nodes
    // ----------------------------------

    const frontendIpConfiguration_name: string = 'stg_lb_ipconf_web';
    const stg_lb_web = new Lb(this, 'stg_lb_web', {
      name: 'stg_lb_web',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      frontendIpConfiguration: [
        {
          name: frontendIpConfiguration_name,
          publicIpAddressId: stg_public_ip_lb.id
        }
      ]
    });

    const stg_lb_probe_https_web = new LbProbe(this, 'stg_lb_probe_https_web', {
      name: 'stg_lb_probe_https_web',
      resourceGroupName: stg_rg.name,
      loadbalancerId: stg_lb_web.id,
      protocol: 'Tcp', // LB with SKU: Basic does not support 'Https' health check, using 'Tcp' instead.
      // requestPath: '/', // Todo: Create health check endpoints for NGINX for quick response with a 200 OK.
      port: 443,
      intervalInSeconds: 15,
      numberOfProbes: 2
    });

    const stg_lb_probe_http_web = new LbProbe(this, 'stg_lb_probe_http_web', {
      name: 'stg_lb_probe_http_web',
      resourceGroupName: stg_rg.name,
      loadbalancerId: stg_lb_web.id,
      protocol: 'Http',
      requestPath: '/', // Todo: Create health check endpoints for NGINX for quick response with a 200 OK.
      port: 80,
      intervalInSeconds: 15,
      numberOfProbes: 2
    });

    const stg_lb_bap_web = new LbBackendAddressPool(this, 'stg_lb_bap_web', {
      name: 'stg_lb_bap_web',
      resourceGroupName: stg_rg.name,
      loadbalancerId: stg_lb_web.id
    });

    new LbRule(this, 'stg_lb_rule_https_web', {
      name: 'stg_lb_rule_https_web',
      resourceGroupName: stg_rg.name,
      loadbalancerId: stg_lb_web.id,
      protocol: 'Tcp',
      frontendPort: 443,
      backendPort: 443,
      frontendIpConfigurationName: frontendIpConfiguration_name,
      backendAddressPoolId: stg_lb_bap_web.id,
      probeId: stg_lb_probe_https_web.id
    });

    new LbRule(this, 'stg_lb_rule_http_web', {
      name: 'stg_lb_rule_http_web',
      resourceGroupName: stg_rg.name,
      loadbalancerId: stg_lb_web.id,
      protocol: 'Tcp',
      frontendPort: 80,
      backendPort: 80,
      frontendIpConfigurationName: frontendIpConfiguration_name,
      backendAddressPoolId: stg_lb_bap_web.id,
      probeId: stg_lb_probe_http_web.id
    });

    // ----------------------------------
    // Virtual Machine - Web Proxy
    // ----------------------------------

    const stg_ni_web = new NetworkInterface(this, 'stg_ni_web', {
      name: 'stg_ni_web',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_web',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.10',
          publicIpAddressId: stg_public_ip_web.id
        }
      ]
    });

    new NetworkInterfaceBackendAddressPoolAssociation(this, 'stg_nibapa_web', {
      networkInterfaceId: stg_ni_web.id,
      ipConfigurationName: 'stg_ipconf_web',
      backendAddressPoolId: stg_lb_bap_web.id
    });

    const stg_nsg_web = new NetworkSecurityGroup(this, 'stg_nsg_web', {
      name: 'stg_nsg_web',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_web', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_web.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_http_web', {
      name: 'http',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_web.name,
      direction: 'Inbound',
      priority: 300,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '80',
      destinationAddressPrefix: '*'
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_https_web', {
      name: 'https',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_web.name,
      direction: 'Inbound',
      priority: 400,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '443',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_web', {
      name: 'stg_vm_web',
      computerName: 'webproxy',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_web.id],
      osDisk: [
        {
          name: 'stg_osdisk_web',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - API Alpha
    // ----------------------------------

    const stg_ni_api_alpha = new NetworkInterface(this, 'stg_ni_api_alpha', {
      name: 'stg_ni_api_alpha',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_api_alpha',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.20',
          publicIpAddressId: stg_public_ip_api_alpha.id
        }
      ]
    });

    const stg_nsg_api_alpha = new NetworkSecurityGroup(
      this,
      'stg_nsg_api_alpha',
      {
        name: 'stg_nsg_api_alpha',
        resourceGroupName: stg_rg.name,
        location: stg_rg.location
      }
    );

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_api_alpha', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_api_alpha.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_api_alpha', {
      name: 'stg_vm_api_alpha',
      computerName: 'apialpha',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_api_alpha.id],
      osDisk: [
        {
          name: 'stg_osdisk_api_alpha',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - API Bravo
    // ----------------------------------

    const stg_ni_api_bravo = new NetworkInterface(this, 'stg_ni_api_bravo', {
      name: 'stg_ni_api_bravo',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_api_bravo',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.21',
          publicIpAddressId: stg_public_ip_api_bravo.id
        }
      ]
    });

    const stg_nsg_api_bravo = new NetworkSecurityGroup(
      this,
      'stg_nsg_api_bravo',
      {
        name: 'stg_nsg_api_bravo',
        resourceGroupName: stg_rg.name,
        location: stg_rg.location
      }
    );

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_api_bravo', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_api_bravo.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_api_bravo', {
      name: 'stg_vm_api_bravo',
      computerName: 'apibravo',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_api_bravo.id],
      osDisk: [
        {
          name: 'stg_osdisk_api_bravo',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - Web Client (eng)
    // ----------------------------------

    const stg_ni_clt_eng = new NetworkInterface(this, 'stg_ni_clt_eng', {
      name: 'stg_ni_clt_eng',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_clt_eng',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.30',
          publicIpAddressId: stg_public_ip_clt_eng.id
        }
      ]
    });

    const stg_nsg_clt_eng = new NetworkSecurityGroup(this, 'stg_nsg_clt_eng', {
      name: 'stg_nsg_clt_eng',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_clt_eng', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_clt_eng.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_clt_eng', {
      name: 'stg_vm_clt_eng',
      computerName: 'clteng',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_clt_eng.id],
      osDisk: [
        {
          name: 'stg_osdisk_clt_eng',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - Web Client (chn)
    // ----------------------------------

    const stg_ni_clt_chn = new NetworkInterface(this, 'stg_ni_clt_chn', {
      name: 'stg_ni_clt_chn',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_clt_chn',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.40',
          publicIpAddressId: stg_public_ip_clt_chn.id
        }
      ]
    });

    const stg_nsg_clt_chn = new NetworkSecurityGroup(this, 'stg_nsg_clt_chn', {
      name: 'stg_nsg_clt_chn',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_clt_chn', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_clt_chn.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_clt_chn', {
      name: 'stg_vm_clt_chn',
      computerName: 'cltchn',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_clt_chn.id],
      osDisk: [
        {
          name: 'stg_osdisk_clt_chn',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - Web Client (esp)
    // ----------------------------------

    const stg_ni_clt_esp = new NetworkInterface(this, 'stg_ni_clt_esp', {
      name: 'stg_ni_clt_esp',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_clt_esp',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.50',
          publicIpAddressId: stg_public_ip_clt_esp.id
        }
      ]
    });

    const stg_nsg_clt_esp = new NetworkSecurityGroup(this, 'stg_nsg_clt_esp', {
      name: 'stg_nsg_clt_esp',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_clt_esp', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_clt_esp.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_clt_esp', {
      name: 'stg_vm_clt_esp',
      computerName: 'cltesp',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_clt_esp.id],
      osDisk: [
        {
          name: 'stg_osdisk_clt_esp',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - Web Client (cnt)
    // ----------------------------------

    const stg_ni_clt_cnt = new NetworkInterface(this, 'stg_ni_clt_cnt', {
      name: 'stg_ni_clt_cnt',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_clt_cnt',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.60',
          publicIpAddressId: stg_public_ip_clt_cnt.id
        }
      ]
    });

    const stg_nsg_clt_cnt = new NetworkSecurityGroup(this, 'stg_nsg_clt_cnt', {
      name: 'stg_nsg_clt_cnt',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_clt_cnt', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_clt_cnt.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_clt_cnt', {
      name: 'stg_vm_clt_cnt',
      computerName: 'cltcnt',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_clt_cnt.id],
      osDisk: [
        {
          name: 'stg_osdisk_clt_cnt',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - Web Client (ita)
    // ----------------------------------

    const stg_ni_clt_ita = new NetworkInterface(this, 'stg_ni_clt_ita', {
      name: 'stg_ni_clt_ita',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_clt_ita',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.70',
          publicIpAddressId: stg_public_ip_clt_ita.id
        }
      ]
    });

    const stg_nsg_clt_ita = new NetworkSecurityGroup(this, 'stg_nsg_clt_ita', {
      name: 'stg_nsg_clt_ita',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_clt_ita', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_clt_ita.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_clt_ita', {
      name: 'stg_vm_clt_ita',
      computerName: 'cltita',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_clt_ita.id],
      osDisk: [
        {
          name: 'stg_osdisk_clt_ita',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // ----------------------------------
    // Virtual Machine - Web Client (por)
    // ----------------------------------

    const stg_ni_clt_por = new NetworkInterface(this, 'stg_ni_clt_por', {
      name: 'stg_ni_clt_por',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      ipConfiguration: [
        {
          name: 'stg_ipconf_clt_por',
          primary: true,
          subnetId: stg_subnet.id,
          privateIpAddressAllocation: 'Static',
          privateIpAddress: '10.240.0.80',
          publicIpAddressId: stg_public_ip_clt_por.id
        }
      ]
    });

    const stg_nsg_clt_por = new NetworkSecurityGroup(this, 'stg_nsg_clt_por', {
      name: 'stg_nsg_clt_por',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location
    });

    new NetworkSecurityRule(this, 'stg_nsg_rule_ssh_clt_por', {
      name: 'SSH',
      resourceGroupName: stg_rg.name,
      networkSecurityGroupName: stg_nsg_clt_por.name,
      direction: 'Inbound',
      priority: 200,
      access: 'Allow',
      protocol: 'Tcp',
      sourcePortRange: '*',
      sourceAddressPrefix: '*',
      destinationPortRange: '22',
      destinationAddressPrefix: '*'
    });

    new LinuxVirtualMachine(this, 'stg_vm_clt_por', {
      name: 'stg_vm_clt_por',
      computerName: 'cltpor',
      resourceGroupName: stg_rg.name,
      location: stg_rg.location,
      size: 'Standard_B2s',
      adminUsername: 'freecodecamp',
      adminSshKey: [
        {
          username: 'freecodecamp',
          publicKey: ssh_public_key
        }
      ],
      networkInterfaceIds: [stg_ni_clt_por.id],
      osDisk: [
        {
          name: 'stg_osdisk_clt_por',
          caching: 'ReadWrite',
          storageAccountType: 'Standard_LRS'
        }
      ],
      sourceImageReference: [
        {
          publisher: 'Canonical',
          offer: 'UbuntuServer',
          sku: '18.04-LTS',
          version: 'latest'
        }
      ],
      // https://github.com/freeCodeCamp/infra/blob/master/cloud-init/basic.yaml
      customData: custom_data
    });

    // End of Stack
  }
}

const app = new App();
const stack = new StagingStack(app, 'staging-stack', keys);
new RemoteBackend(stack, {
  hostname: 'app.terraform.io',
  organization: 'freecodecamp',
  workspaces: {
    name: 'stg_tfws'
  }
});

app.synth();
