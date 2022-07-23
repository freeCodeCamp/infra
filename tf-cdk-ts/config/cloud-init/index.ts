import yaml from 'js-yaml';

import { BASE64_ENCODED_CUSTOM_DATA, CLUSTER_ENCRYPTION_KEY } from '../env';
import { VMList } from '../../utils';

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

export const getCloudInitForNomadConsulCluster = ({
  dataCenter,
  serverList = [],
  privateIP = '127.0.0.1',
  clusterServerAgent = false
}: {
  dataCenter: string;
  serverList?: Array<VMList>;
  privateIP?: string;
  clusterServerAgent?: boolean;
}) => {
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
    content: |
      datacenter = "${dataCenter}"
      data_dir = "/opt/consul"

      encrypt = "${CLUSTER_ENCRYPTION_KEY}"
      verify_incoming = true
      verify_outgoing = true
      verify_server_hostname = true

      bind_addr = "${privateIP}"
      client_addr = "${privateIP}"
${
  clusterServerAgent
    ? `
      server = true
      bootstrap_expect = ${serverList.length}

      connect {
        enabled = true
      }

      # addresses {
      #   grpc = "${privateIP}"
      # }

      # ports {
      #   grpc  = 8502
      # }
`
    : ''
}
  - path: /etc/nomad.d/nomad.hcl
    owner: nomad:nomad
    content: |
      datacenter = "${dataCenter}"
      data_dir   = "/opt/nomad"
      bind_addr = "${privateIP}"
${
  clusterServerAgent
    ? `
      server {
        enabled          = true
        bootstrap_expect = ${serverList.length}
      }
`
    : `
      client {
        enabled = true
      }
`
}
  - path: /usr/lib/systemd/system/consul.service
    owner: root:root
    content: |
      [Unit]
      Description=Consul ${clusterServerAgent ? 'Server' : 'Client'} Agent
      Documentation=https://www.consul.io/
      Requires=network-online.target
      After=network-online.target
      ConditionFileNotEmpty=/etc/consul.d/consul.hcl

      [Service]
      EnvironmentFile=-/etc/consul.d/consul.env
      User=consul
      Group=consul
      ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d/
      ExecReload=/bin/kill --signal HUP $MAINPID
      KillMode=process
      KillSignal=SIGTERM
      Restart=on-failure
      RestartSec=2
      StartLimitBurst=0
      StartLimitIntervalSec=10
      LimitNOFILE=65536

      [Install]
      WantedBy=multi-user.target

  - path: /usr/lib/systemd/system/nomad.service
    owner: root:root
    content: |
      [Unit]
      Description=Nomad ${clusterServerAgent ? 'Server' : 'Client'} Agent
      Wants=network-online.target
      After=network-online.target
      Wants=consul.service
      After=consul.service


      [Service]
      EnvironmentFile=/etc/nomad.d/nomad.env
      ExecReload=/bin/kill -HUP $MAINPID
      ExecStart=/usr/bin/nomad agent -config /etc/nomad.d
      KillMode=process
      KillSignal=SIGINT
      LimitNOFILE=65536
      LimitNPROC=infinity
      Restart=on-failure
      RestartSec=2
      StartLimitBurst=0
      StartLimitIntervalSec=10
      TasksMax=infinity
      OOMScoreAdjust=-1000

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl restart consul
  - systemctl restart nomad
  - systemctl status consul
  - systemctl status nomad
`;

  testSource(source, false); // Change the value to true to debug the cloud-init data
  // console.log(source); // Uncomment to debug the cloud-init data

  // Encode the cloud-init data to base64 from the 'source'
  return Buffer.from(source, 'utf8').toString('base64');
};
