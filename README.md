# docker-swarm-config

> Docker stack configs for our Docker swarm clusters

## Usage

1. On manager node - Create docker swarm cluster (if needed).

   ```shell
   docker swarm init
   docker swarm join-token manager
   ```

2. On worker nodes - Join the cluster (if needed).

    ```shell
    docker swarm join --token <token> <ip>:<port>
    ```
 
3. On all nodes - Add labels to the nodes in the cluster. 

   > [!IMPORTANT]
   > Labels are used for placement constraints in the docker stack templates.

   Here are some example lables for the nodes. Adjust as needed

   - On the manager node
   
     ```shell
     # Label for the portainer stack
     docker node update --label-add "portainer=true" <node id>
     ```

   - On the worker nodes

     JAMStack news

     ```shell
     # Common 
     docker node update --label-add "jms.enabled=true" <node id>
   
     # Environment specific
     docker node update --label-add "jms.variant=dev" <node id>
     docker node update --label-add "jms.variant=org" <node id>
     ```

     API
     
     ```shell
     # Common 
     docker node update --label-add "api.enabled=true" <node id>
   
     # Environment specific
     docker node update --label-add "api.variant=dev" <node id>
     docker node update --label-add "api.variant=org" <node id>
     ```
   
4. Deploy Portainer. 

   > [!WARNING]
   > ~~These instructions may not work. Docker swarm is adding multiple networks to the services for some reason.~~
   > 
   > Use the stack defined in [portainer.yml](./stacks/portainer/portainer.yml).

   ```shell
   docker stack deploy -c portainer.yml portainer
   ```

5. Complete the Portainer setup wizard & add the cluster to Portainer.

6. Add the container registry details to Portainer.

7. Deploy all the remaining stacks via Portainer. Note that you should not manage the portainer stack from within Portainer UI.
