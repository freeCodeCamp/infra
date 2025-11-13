## Usage

This stack defines all the services for the housekeeping apps. See comments in the stack file for details.

### Gantry Auto-Update Service

**Authentication Requirements:**
- Uses host Docker credentials from `/home/freecodecamp/.docker/config.json`
- Requires `--with-registry-auth` (set via `GANTRY_UPDATE_OPTIONS`) to propagate credentials to worker nodes
- Credentials must be valid and updated if expired

**Directory Requirements:**
- Mount `/home/freecodecamp/.docker:/root/.docker` as **writable** (buildx needs write access)
- Ensure `/home/freecodecamp/.docker/buildx/` directory exists on manager node

**Google Chat Notifications:**
- Create webhook in Google Chat: Space menu → Apps & integrations → Webhooks → Add webhook
- Set environment variable with webhook URL:
```bash
export GANTRY_GCHAT_WEBHOOK_URL="gchat://workspace/key/token"
# Or use direct URL:
export GANTRY_GCHAT_WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/..."
```

**Deployment:**
```bash
# Ensure correct ownership and permissions
sudo chown -R freecodecamp:freecodecamp /home/freecodecamp/.docker
sudo chmod -R u+w /home/freecodecamp/.docker

# Set notification webhook (optional)
export GANTRY_GCHAT_WEBHOOK_URL="gchat://workspace/key/token"

# Deploy stack
docker stack deploy -c docker/swarm/stacks/oncall/stack-oncall.yml oncall
```

**Note:** The update service runs on the manager node via cronjob scheduling (managed by `svc-cronjob`).
