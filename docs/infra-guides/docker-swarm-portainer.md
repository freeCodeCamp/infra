# Portainer Stack

Docker Swarm stack configuration for Portainer CE with secure external access via Tailscale.

## Overview

The Portainer stack provides a web-based management interface for Docker Swarm clusters. External access is secured through Tailscale networking with trusted origins configuration for CSRF protection.

## Architecture

```
External Request → Tailscale (443) → Portainer (9000)
```

### Components

| Service       | Purpose                             | Ports                           |
| ------------- | ----------------------------------- | ------------------------------- |
| **portainer** | Docker Swarm management UI          | 9000:9000, 9443:9443, 8000:8000 |
| **agent**     | Portainer agent (deployed globally) | -                               |

### Port Configuration

- **Port 9000**: Production access via Tailscale
- **Port 9443**: Portainer HTTPS interface
- **Port 8000**: Portainer Edge Agent tunnel

Portainer uses the `--trusted-origins` flag to allow access from the Tailscale domain, eliminating CSRF validation issues. See: https://www.portainer.io/blog/origin-invalid-errors-with-portainer-2-27-7-behind-reverse-proxies

## Prerequisites

- Docker Swarm cluster initialized
- Node labeled with `portainer=true` for service placement

## Deployment

### 1. Deploy Stack

Set the environment variable and deploy in one command:

```shell
TAILSCALE_HOSTNAME=your-device.your-tailnet.ts.net docker stack deploy -c stack-portainer.yml portainer
```

Or export the variable first, then deploy:

```shell
export TAILSCALE_HOSTNAME=your-device.your-tailnet.ts.net
docker stack deploy -c stack-portainer.yml portainer
```

### 3. Configure Tailscale Access

```shell
sudo tailscale serve --bg --tls-terminated-tcp 443 tcp://127.0.0.1:9000
```

**Important**: Use `127.0.0.1` instead of `localhost` for proper Tailscale connectivity.

## Access

- **Production**: `https://your-device.your-tailnet.ts.net`
- **HTTPS**: `https://localhost:9443`

## Notes

- Portainer should not manage itself to prevent configuration conflicts
- The stack uses placement constraints requiring node labels for proper deployment
- Trusted origins configuration eliminates CSRF validation errors when accessing through Tailscale
- Direct connection works reliably with proper `127.0.0.1` addressing
