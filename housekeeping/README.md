> Our Ansible configuration and documentation for housekeeping on some of our instances.

> Warning:
> This currently works for [@raisedadead](https://github.com/raisedadead)'s local setup only. More instructions are coming soon.

Here is an example command:

```console
ansible-playbook -i hosts playbooks/uptime.yml --extra-vars "variable_host=ghost"
```
