# news-config

> Temporary docker stack configs before we move to Nomad

## Usage

1. Create docker swarm cluster as needed.
   
   ```shell
   docker swarm init
   docker swarm join-token manager
   ```
2. Add worker nodes to the cluster.

    ```shell
    docker swarm join --token <token> <ip>:<port>
    ```
 
4. **Important:** Add labels to the nodes in the cluster. This will be used for placement constraints in the docker stack files.

   Add the following labels to the nodes:

   - On the manager node that will run portainer
   
     ```shell
     docker node update --label-add "portainer=true" <node id>
     ```

   - On all nodes that will run the JMS instances

     ```shell
     docker node update --label-add "jms.enabled=true" <node id>
     ```

   - On all staging nodes
   
     ```shell
     docker node update --label-add "jms.variant=dev" <node id>
     ```

   - On all production nodes
   
     ```shell
     docker node update --label-add "jms.variant=org" <node id>
     ```
5. Login to the private container registry.
   
6. **Important:** Deploy Portainer. 

   ~~:warning: Warning :warning: These instructions may not work. Docker swarm is adding multiple networks to the services for some reason.~~
   
   Use the stack defined in [portainer-stack.yml](./stacks/portainer/portainer-stack.yml).

   ```shell
   docker stack deploy -c portainer-stack.yml portainer
   ```

7. Complete the Portainer setup wizard & add the cluster to Portainer.

8. Add the container registry details to Portainer.
   
9. Deploy all the remaining stacks via Portainer.
