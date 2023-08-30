> Temporary docker stack configs before we move to Nomad

Deployment Notes:

1. Add the docker node label `portainer=true` on ONLY one of the manager nodes.
2. Add the docker node label `jms=true` on all the nodes.
3. Deploy the portainer stack first.
4. Connect to the swarm cluster from the Portainer UI.
5. Deploy the rest of the stacks.
