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

3. Enable the docker host API on one of the manager nodes in the cluster. This will be used by Portainer to manage the cluster.

   ```shell
   sudo systemctl edit docker.service
   ```
   
   Add the following lines to the file:
   ```unit
   [Service]
   ExecStart=
   ExecStart=... -H tcp://<ip>:<port>
   ```

   ```shell
   sudo systemctl daemon-reload
   sudo systemctl restart docker.service
   ```
 
4. **Important:** Add labels to the nodes in the cluster. This will be used for placement constraints in the docker stack files.

   Add the following labels to the nodes that will run the JMS services:
   ```shell
   docker node update --label-add "jms=dev" <node id for the staging    worker nodes>
   docker node update --label-add "jms=org" <node id for the production worker nodes>
   ```
   
5. **Important:** Deploy Portainer in `sudo` mode, because portainer needs to manage docker resources like networks and more. 

   > :warning: Warning :warning: These instructions may not work. Docker swarm is adding multiple networks to the services for some reason
   
   Use the stack defined in [portainer-stack.yml](./stacks/portainer/portainer-stack.yml).

   ```shell
   sudo docker stack deploy -c portainer-stack.yml portainer
   ```

6. Complete the Portainer setup wizard & add the cluster to Portainer.

7. Add the container registry details to Portainer.