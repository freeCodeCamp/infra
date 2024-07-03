#cloud-config
# This file is uploaded to /etc/cloud/cloud.cfg.d/99_custom_cloud_init.cfg
# and is used to configure cloud-init on the first boot of the instance.
users:
  - name: freecodecamp
    groups:
      - sudo
      - docker
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_import_id:
      - gh:camperbot
final_message: "Setup complete"
