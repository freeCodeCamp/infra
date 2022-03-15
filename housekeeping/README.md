> Our Ansible configuration and documentation for housekeeping on some of our
> instances.

Here is an example command:

```console
ansible-playbook -i hosts playbooks/uptime.yml --extra-vars "variable_host=ghost"
```
