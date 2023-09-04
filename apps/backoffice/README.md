# Usage

Start the backoffice with the following commands:

```shell
mkdir -p data/portainer_data
docker compose up -d
```

Expose the app over tailscale:

```shell
sudo tailscale serve tls-terminated-tcp:443 tcp://localhost:9000
```

Access the app at `https://backoffice.<magic-dns-tailnet>.ts.net`
