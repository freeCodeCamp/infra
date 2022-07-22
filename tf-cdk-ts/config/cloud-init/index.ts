import yaml from 'js-yaml';

import { BASE64_ENCODED_CUSTOM_DATA } from '../env';
import { getCloudAutoJoinString, VMList } from '../../utils';

const testSource = (source: string, debugCloudInit: boolean): boolean => {
  // Test the cloud-init data Syntax
  try {
    const jsonCloudInit = yaml.load(source);
    if (debugCloudInit) {
      console.log(yaml.dump(jsonCloudInit));
    }
    return true;
  } catch (e) {
    throw new Error(`

      Error:
      Cloud-init data is not valid.

      ${e}
      `);
  }
};

export const getCloudInitForNomadConsulServers = (
  serverList: Array<VMList>
) => {
  // Decode the intial base64 encoded cloud-init data
  const intialCloudInit = Buffer.from(
    BASE64_ENCODED_CUSTOM_DATA || '',
    'base64'
  ).toString('ascii');

  // Append more cloud-init data
  const source = `${intialCloudInit}
write_files:
  - path: /etc/consul.d/consul.hcl
    owner: consul:consul
    permissions: 0640
    content: |
      datacenter = "dc1"
      data_dir = "/opt/consul"

      # Uncomment & Update the following lines after provisioning the cluster

      # encrypt = "CHANGE THIS TO A VALID KEY"
      # verify_incoming = true
      # verify_outgoing = true
      # verify_server_hostname = true

      # ca_file = "<Consul configuration directory>/certs/consul-agent-ca.pem"
      # cert_file = "<Consul configuration directory>/certs/dc1-server-consul-0.pem"
      # key_file = "<Consul configuration directory>/certs/dc1-server-consul-0-key.pem"

      # auto_encrypt {
      #   allow_tls = true
      # }

      # acl {
      #   enabled = true
      #   default_policy = "allow"
      #   enable_token_persistence = true
      # }

      # performance {
      #   raft_multiplier = 1
      # }

  - path: /etc/consul.d/server.hcl
    owner: consul:consul
    permissions: 0640
    content: |
      server = true
      bootstrap_expect = ${serverList.length}

      # Uncomment & Update the following lines after provisioning the cluster
      connect {
        enabled = true
      }

      # addresses {
      #   grpc = "127.0.0.1"
      # }

      # ports {
      #   grpc  = 8502
      # }

      ui_config {
        enabled = true
      }

  - path: /etc/nomad.d/nomad.hcl
    owner: nomad:nomad
    permissions: 0755
    content: |
      datacenter = "dc1"
      data_dir   = "/opt/nomad"

  - path: '/etc/nomad.d/server.hcl'
    owner: nomad:nomad
    permissions: 0755
    content: |
      server {
        enabled          = true
        bootstrap_expect =
        server_join {
          retry_join = [ ${getCloudAutoJoinString(serverList)} ]
          retry_max = 3
          retry_interval = "30s"
        }
      }

  - path: /etc/systemd/system/consul.service
    owner: root:root
    content: |
      [Unit]
      Description=Consul Server
      Documentation=https://www.consul.io/
      Requires=network-online.target
      After=network-online.target
      ConditionFileNotEmpty=/etc/consul.d/consul.hcl

      [Service]
      EnvironmentFile=-/etc/consul.d/consul.env
      User=consul
      Group=consul
      ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
      ExecReload=/bin/kill --signal HUP $MAINPID
      KillMode=process
      KillSignal=SIGTERM
      Restart=on-failure
      LimitNOFILE=65536

      [Install]
      WantedBy=multi-user.target

  - path: /etc/systemd/system/nomad.service
    owner: root:root
    content: |
      [Unit]
      Description=Nomad Server
      Documentation=https://www.nomadproject.io/docs/
      Requires=network-online.target
      After=network-online.target

      [Service]
      User=nomad
      Group=nomad
      ExecReload=/bin/kill -HUP $MAINPID
      ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
      KillMode=process
      KillSignal=SIGINT
      LimitNOFILE=infinity
      LimitNPROC=infinity
      Restart=on-failure
      RestartSec=2
      StartLimitBurst=0
      StartLimitIntervalSec=10
      TasksMax=infinity

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl enable consul
  - systemctl start consul
  - systemctl enable nomad
  - systemctl start nomad
  - systemctl status consul
  - systemctl status nomad
`;

  testSource(source, false); // Change the value to true to debug the cloud-init data
  // console.log (source);   // Uncomment to debug the cloud-init data

  // Encode the cloud-init data to base64 from the 'source'
  const cloudInitBase64 = Buffer.from(source, 'utf8').toString('base64');

  return cloudInitBase64;
};

export const getCloudInitForNomadConsulClients =
  (/*serverList: Array<ServerList>*/) => {
    // Decode the intial base64 encoded cloud-init data
    const intialCloudInit = Buffer.from(
      BASE64_ENCODED_CUSTOM_DATA || '',
      'base64'
    ).toString('ascii');

    // Append more cloud-init data
    const source = `${intialCloudInit}
write_files:
  - path: /etc/consul.d/consul.hcl
    owner: consul:consul
    permissions: 0640
    content: |
      datacenter = "dc1"
      data_dir = "/opt/consul"

      # Uncomment & Update the following lines after provisioning the cluster

      # encrypt = "CHANGE THIS TO A VALID KEY"
      # verify_incoming = true
      # verify_outgoing = true
      # verify_server_hostname = true

      # ca_file = "<Consul configuration directory>/certs/consul-agent-ca.pem"

      # auto_encrypt {
      #   allow_tls = true
      # }

      # acl {
      #   enabled = true
      #   default_policy = "allow"
      #   enable_token_persistence = true
      # }

      # performance {
      #   raft_multiplier = 1
      # }

  - path: '/etc/nomad.d/nomad.hcl'
    owner: nomad:nomad
    permissions: 0755
    content: |
      datacenter = "dc1"
      data_dir   = "/opt/nomad"

  - path: '/etc/nomad.d/client.hcl'
    owner: nomad:nomad
    permissions: 0755
    content: |
      client {
        enabled = true
      }

  - path: /etc/systemd/system/consul.service
    owner: root:root
    content: |
      [Unit]
      Description=Consul Server
      Documentation=https://www.consul.io/
      Requires=network-online.target
      After=network-online.target
      ConditionFileNotEmpty=/etc/consul.d/consul.hcl

      [Service]
      EnvironmentFile=-/etc/consul.d/consul.env
      User=consul
      Group=consul
      ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
      ExecReload=/bin/kill --signal HUP $MAINPID
      KillMode=process
      KillSignal=SIGTERM
      Restart=on-failure
      LimitNOFILE=65536

      [Install]
      WantedBy=multi-user.target

  - path: '/etc/systemd/system/nomad.service'
    owner: root:root
    content: |
      [Unit]
      Description=Nomad Client
      Documentation=https://www.nomadproject.io/docs/
      Requires=network-online.target
      After=network-online.target

      [Service]
      User=root
      Group=root
      ExecReload=/bin/kill -HUP $MAINPID
      ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
      KillMode=process
      KillSignal=SIGINT
      LimitNOFILE=infinity
      LimitNPROC=infinity
      Restart=on-failure
      RestartSec=2
      StartLimitBurst=0
      StartLimitIntervalSec=10
      TasksMax=infinity

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl enable nomad
  - systemctl start nomad
  - systemctl status nomad
`;

    testSource(source, false); // Change the value to true to debug the cloud-init data
    // console.log (source);   // Uncomment to debug the cloud-init data

    // Encode the cloud-init data to base64 from the 'source'
    const cloudInitBase64 = Buffer.from(source, 'utf8').toString('base64');

    return cloudInitBase64;
  };
