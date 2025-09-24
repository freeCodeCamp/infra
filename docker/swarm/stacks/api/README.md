# API Stack

Docker Swarm stack configuration for freeCodeCamp Learn API.

## Services

| Service           | Port      | Health Check   |
| ----------------- | --------- | -------------- |
| **svc-api-alpha** | 2345:3000 | `/status/ping` |
| **svc-api-bravo** | 2346:3000 | `/status/ping` |

## Quick Start

### 1. Prerequisites

- Docker Swarm cluster initialized
- Nodes labeled with `api.enabled=true` and `api.variant=${DEPLOYMENT_TLD}`

### 2. Deploy with Encrypted Secrets

```bash
# Set required variables
export AGE_ENCRYPTED_ASC_SECRETS="<encrypted-secrets>"
export AGE_SECRET_KEY="<decryption-key>"
export DEPLOYMENT_VERSION="<version>"
export DEPLOYMENT_TLD="dev"  # or "org" for production

# Deploy in 2 steps
make decrypt    # Decrypt secrets to .env file
source .env     # Source environment variables
make deploy     # Deploy stack (auto-detects staging/production)
```

### 3. Deploy with Manual Variables

```bash
# Copy template and set values
cp .env.sample .env
# Edit .env with actual values...

source .env     # Source environment variables
make deploy     # Deploy stack
```

## Available Commands

- `make help` - Show all available commands
- `make decrypt` - Decrypt age-encrypted secrets to `.env` file
- `make validate` - Validate all required environment variables
- `make config` - Validate Docker stack configuration
- `make deploy` - Deploy stack (auto-detects dev/prod from DEPLOYMENT_TLD)
- `make debug` - Generate debug configuration file
- `make clean` - Remove temporary files

## Environment Variables

See `.env.sample` for the complete and current list.

## Manual Deployment (Advanced)

If you need to deploy without the Makefile:

### 1. Label Nodes

```bash
docker node update --label-add "api.enabled=true" <node-id>
docker node update --label-add "api.variant=dev" <node-id>  # or "org" for production
```

### 2. Validate and Deploy

```bash
# Validate environment
./scripts/validate-env.sh

# Validate configuration
docker stack config -c stack-api.yml > /dev/null

# Deploy stack manually
docker stack deploy -c stack-api.yml --prune --with-registry-auth --detach=false <stack-name>
```

**Stack naming convention:**

- `DEPLOYMENT_TLD=dev` → `stg-api`
- `DEPLOYMENT_TLD=org` → `prd-api`

## Notes

- Use `make help` to see all available deployment commands
- Use `.env.sample` as template for required variables
- Scripts validate environment and handle age decryption automatically
- Docker Swarm doesn't support env files - source variables before deployment
- Services use host networking mode with placement constraints
- Health checks via `/status/ping?checker=swarm-manager`
- Loki logging with structured JSON pipeline
- Rolling updates with automatic rollback on 30% failure threshold
