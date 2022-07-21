import { custom_data } from '../env';
import { getCloudAutoJoinString, VMList } from '../../utils';

//
// Decode the cloud-init script, append more customization and encode it again
//

export const getCloudInitForNomadServers = (serverList: Array<VMList>) => {
  return Buffer.from(
    `${Buffer.from(custom_data, 'base64').toString('ascii')}
write_files:
  - path: '/etc/nomad.d/server.hcl'
    owner: nomad:nomad
    content: |
      server {
        enabled          = true
        bootstrap_expect = 3
        server_join {
          retry_join = [${getCloudAutoJoinString(serverList)}]
          retry_max = 3
          retry_interval = "30s"
        }
      }
  - path: '/etc/systemd/system/nomad.service'
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
  - systemctl enable nomad
  - systemctl start nomad
  - systemctl status nomad
`
  ).toString('base64');
};

export const getCloudInitForNomadClient =
  (/*serverList: Array<ServerList>*/) => {
    return Buffer.from(
      `${Buffer.from(custom_data, 'base64').toString('ascii')}
write_files:
  - path: '/etc/nomad.d/client.hcl'
    owner: nomad:nomad
    content: |
      client {
        enabled = true
      }
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
`
    ).toString('base64');
  };
