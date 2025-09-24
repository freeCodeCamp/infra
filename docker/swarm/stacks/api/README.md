## Usage

This stack defines all the services for the API. Name the stacks as per the environment ex: `prd-api`, etc. Set up the env values from the `.env.sample` file within the Portainer UI.

**Caddyfile**

The Caddyfile is used to proxy the API to the correct port. It is located in the [`Caddyfile`](./Caddyfile) file. You will need to create a new Docker config for each new version of the file. Check the stack file for the correct name, and create the config within the `configs` section of Portainer. You can then set the `CADDY_CONFIG_NAME` environment variable to the name of the config you created.
