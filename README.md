# news-config

> Temporary docker stack configs before we move to Nomad

## Usage

1. Create docker swarm cluster as needed.
   
   ```shell
   docker swarm init
   docker swarm join-token manager
   ```
2. Add manager nodes to the cluster.

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
   docker node update --label-add "jms=true" <node-name>
   ```
   
5. Deploy Portainer to the backoffice VM with docker compose. See details in the [Portainer README](./apps/backoffice/README.md).

6. Complete the Portainer setup wizard & add the cluster to Portainer.

7. Add the container registry details to Portainer.
   
8. Create the news stack in Portainer using the [news-stack.yml](./apps/stacks/news/news-stack.yml) file. Ensure enviroment variables are set as needed.
