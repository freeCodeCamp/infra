# Fast-Track Migration: ingress-nginx → Traefik Gateway API

## ⚠️ Critical Info

- **Deadline**: ingress-nginx maintenance ends March 2026
- **Migration approach**: Two-phase, zero-downtime
- **External apps**: Will NOT be affected during migration
- **Total time**: 1-2 hours active work, 1-2 days validation

## Architecture

```
Phase 1: Both Running          Phase 2: Cutover
┌─────────────────────┐       ┌──────────────────┐
│ ingress-nginx       │       │ Traefik (new)    │
│ (current traffic)   │       │ (all traffic)    │
│ LB IP: X.X.X.X      │       │ LB IP: Y.Y.Y.Y   │
└─────────────────────┘       └──────────────────┘
         ↓                             ↓
┌─────────────────────┐       ┌──────────────────┐
│ Traefik (testing)   │       │ ingress-nginx    │
│ LB IP: Y.Y.Y.Y      │       │ (removed)        │
└─────────────────────┘       └──────────────────┘
```

## Prerequisites

- `kubectl` configured for o11y cluster
- `helm` installed
- DNS access to update A record for o11y.freecodecamp.net
- 30-60 minutes of focused time

---

## Phase 1: Deploy Traefik (Parallel Run)

**Estimated time: 30 minutes**

### Step 1: Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

Verify:
```bash
kubectl get crd | grep gateway
```

Expected output:
```
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
...
```

### Step 2: Add Traefik Helm repo

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```

### Step 3: Install Traefik in traefik-system namespace

```bash
helm upgrade traefik traefik/traefik \
  --install \
  --namespace traefik-system \
  --create-namespace \
  -f charts/traefik/values.yaml
```

**Key point**: This creates a NEW LoadBalancer (separate from ingress-nginx)

### Step 4: Get Traefik LoadBalancer IP

```bash
kubectl get svc -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Save this IP** - you'll need it for testing!

Example output: `123.45.67.89`

### Step 5: Deploy Gateway API resources

```bash
kubectl apply -f k8s/gateway/gateway.yaml
kubectl apply -f k8s/gateway/httproutes.yaml
```

Verify:
```bash
kubectl get gateway,httproute -n o11y
```

Expected output:
```
NAME                                    CLASS     ADDRESS   PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/o11y-gateway   traefik             True         30s

NAME                                           HOSTNAMES                    AGE
httproute.gateway.networking.k8s.io/grafana-route   ["o11y.freecodecamp.net"]   30s
httproute.gateway.networking.k8s.io/loki-route      ["o11y.freecodecamp.net"]   30s
```

### Step 6: Test with new LoadBalancer IP

**Important**: Use `curl` with `--resolve` to test WITHOUT changing DNS:

```bash
# Get the new Traefik IP
NEW_IP=$(kubectl get svc -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test Grafana
curl -kv --resolve o11y.freecodecamp.net:443:${NEW_IP} https://o11y.freecodecamp.net/

# Test Loki status endpoint
export LOKI_GW_PASSWORD=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_GATEWAY_PASSWORD}' | base64 --decode)
export LOKI_TENANT_ID=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_TENANT_ID}' | base64 --decode)

curl -kv --resolve o11y.freecodecamp.net:443:${NEW_IP} \
  -u "loki:${LOKI_GW_PASSWORD}" \
  -H "X-Scope-OrgID: ${LOKI_TENANT_ID}" \
  https://o11y.freecodecamp.net/loki/ready

# Push a test log entry
curl -kv --resolve o11y.freecodecamp.net:443:${NEW_IP} \
  -H "Content-Type: application/json" \
  -XPOST \
  -u "loki:${LOKI_GW_PASSWORD}" \
  -H "X-Scope-OrgID: ${LOKI_TENANT_ID}" \
  --data-raw "{\"streams\": [{\"stream\": {\"job\": \"migration-test\"}, \"values\": [[\"$(date +%s)000000000\", \"Test from Traefik Gateway\"]]}]}" \
  https://o11y.freecodecamp.net/loki/api/v1/push
```

### Step 7: Add temporary DNS entry for testing (OPTIONAL)

If you want your team to test before full cutover:

1. Add a temporary A record: `o11y-new.freecodecamp.net` → `${NEW_IP}`
2. Test in browser: `https://o11y-new.freecodecamp.net/`
3. Verify Grafana login works
4. Check that Loki datasources are healthy

**At this point**:
- ✅ Both gateways are running
- ✅ Old ingress-nginx: handling ALL production traffic
- ✅ New Traefik: tested and ready
- ✅ External apps: unaffected, still using old ingress

---

## Phase 2: DNS Cutover (5-10 minutes)

**Prerequisites**:
- Phase 1 complete
- Traefik tested and verified
- Scheduled maintenance window (optional, but recommended)

### Step 1: Lower DNS TTL (Do this 24h before cutover if possible)

1. In Cloudflare, set TTL for `o11y.freecodecamp.net` to 300 seconds (5 min)
2. Wait for old TTL to expire

### Step 2: Update DNS A record

```bash
# Get new IP
NEW_IP=$(kubectl get svc -n traefik-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Update DNS: o11y.freecodecamp.net → ${NEW_IP}"
```

1. Update Cloudflare A record for `o11y.freecodecamp.net` to point to `${NEW_IP}`
2. Keep Cloudflare proxy status (orange cloud) as-is

### Step 3: Monitor traffic immediately

```bash
# Watch Traefik logs
kubectl logs -n traefik-system -l app.kubernetes.io/name=traefik --tail=50 -f

# In another terminal, watch Traefik pods
kubectl get pods -n traefik-system -w
```

### Step 4: Verify external apps

Within 5-10 minutes of DNS change:

```bash
# Check Loki is receiving logs
kubectl logs -n o11y -l app.kubernetes.io/name=loki --tail=20

# Check Grafana access logs
kubectl logs -n o11y -l app.kubernetes.io/name=grafana --tail=20
```

**Verify**:
- [ ] Grafana UI loads
- [ ] Loki logs are coming in (check Grafana Explore)
- [ ] No 502/503 errors
- [ ] External apps are pushing logs successfully

### Step 5: Wait 24-48 hours (Soak period)

Keep both gateways running for 1-2 days to ensure:
- DNS propagation complete
- All external apps have switched over
- No issues reported

Monitor:
```bash
# Check ingress-nginx traffic (should approach zero)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50
```

### Step 6: Remove old ingress-nginx

After 24-48 hours with no traffic to old gateway:

```bash
# Remove Ingress resource (keep as backup)
kubectl delete -f k8s/ingress/o11y-ingress.yaml

# Uninstall ingress-nginx
helm uninstall ingress-nginx -n ingress-nginx

# Clean up namespace (optional)
kubectl delete namespace ingress-nginx
```

---

## Rollback Plan

If issues arise during Phase 2:

### Immediate rollback (within 5 minutes)

```bash
# Get old ingress-nginx IP
OLD_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Update DNS back to old IP
echo "Rollback DNS: o11y.freecodecamp.net → ${OLD_IP}"
```

Update Cloudflare A record back to old IP. Traffic will switch back within 5-10 minutes.

### If Traefik has issues but ingress-nginx is already removed

```bash
# Redeploy ingress-nginx
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --install \
  --namespace ingress-nginx \
  --create-namespace \
  -f charts/ingress-nginx/values.yaml

# Reapply old Ingress resource
kubectl apply -f k8s/ingress/o11y-ingress.yaml

# Get IP and update DNS
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

---

## Validation Checklist

### Before DNS cutover:
- [ ] Gateway API CRDs installed
- [ ] Traefik running with 2 replicas
- [ ] Gateway resource status = `PROGRAMMED: True`
- [ ] HTTPRoutes created and attached to Gateway
- [ ] Test with `curl --resolve` succeeds
- [ ] Test log push to Loki succeeds

### After DNS cutover:
- [ ] Grafana UI accessible
- [ ] Grafana datasources healthy (Loki, Prometheus)
- [ ] External apps pushing logs successfully
- [ ] No errors in Traefik logs
- [ ] No 502/503 errors
- [ ] Old ingress-nginx traffic dropping to zero

---

## Troubleshooting

### Gateway status shows "PROGRAMMED: False"

```bash
kubectl describe gateway o11y-gateway -n o11y
```

Look for events/errors. Common issues:
- TLS secret not found
- GatewayClass not installed

### HTTPRoute not routing traffic

```bash
kubectl describe httproute grafana-route -n o11y
```

Check:
- ParentRef matches Gateway name
- Backend service exists and has endpoints

### 502 Bad Gateway

Check backend services:
```bash
kubectl get endpoints -n o11y grafana loki-gateway
```

Ensure pods are running:
```bash
kubectl get pods -n o11y
```

### Loki log ingestion failing

Test directly to service (bypass gateway):
```bash
kubectl port-forward -n o11y svc/loki-gateway 8080:80

curl -v -H "Content-Type: application/json" \
  -u "loki:${LOKI_GW_PASSWORD}" \
  -H "X-Scope-OrgID: ${LOKI_TENANT_ID}" \
  --data-raw "{\"streams\": [{\"stream\": {\"job\": \"test\"}, \"values\": [[\"$(date +%s)000000000\", \"Test\"]]}]}" \
  http://localhost:8080/loki/api/v1/push
```

---

## Post-Migration

### Update documentation

- [ ] Update README.md with new Traefik setup
- [ ] Remove ingress-nginx references
- [ ] Document Gateway API resource locations

### Clean up old files

```bash
# Archive old ingress-nginx config
mkdir -p archive
mv charts/ingress-nginx archive/
mv k8s/ingress/o11y-ingress.yaml archive/
```

### Monitor long-term

Set up alerts for:
- Traefik pod restarts
- Gateway status changes
- HTTPRoute status changes
- Increased error rates

---

## Timeline Summary

| Phase | Duration | Downtime | Risk |
|-------|----------|----------|------|
| Phase 1: Deploy Traefik | 30-60 min | None | Low |
| Testing period | 1-4 hours | None | Low |
| Phase 2: DNS cutover | 5-10 min | ~5 min DNS prop | Low |
| Soak period | 24-48 hours | None | Low |
| Cleanup | 10 min | None | None |

**Total active work**: 1-2 hours
**Total elapsed time**: 2-3 days (including soak period)
**Impact to external apps**: None (transparent switch)

---

## Questions?

- Traefik docs: https://doc.traefik.io/traefik/providers/kubernetes-gateway/
- Gateway API docs: https://gateway-api.sigs.k8s.io/
- Rollback: Just revert DNS to old IP
