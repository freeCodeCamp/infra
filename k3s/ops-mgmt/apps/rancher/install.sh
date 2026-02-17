#!/usr/bin/env bash
set -euo pipefail

# Install Rancher v2.13.2 on ops-mgmt k3s cluster
# Prerequisites:
#   - k3s cluster running with KUBECONFIG exported
#   - Helm 3.x installed
#   - Internet access for chart downloads

RANCHER_VERSION="2.13.2"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.ops-mgmt.ts.net}"
RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:?Must set RANCHER_BOOTSTRAP_PASSWORD (e.g. openssl rand -hex 16)}"

echo "=== Step 1: Add Helm repos ==="
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable 2>/dev/null || true
helm repo add rancher-charts https://charts.rancher.io 2>/dev/null || true
helm repo update

echo "=== Step 2: Install cert-manager ==="
if ! helm status cert-manager -n cert-manager &>/dev/null; then
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --wait
  echo "cert-manager installed"
else
  echo "cert-manager already installed, skipping"
fi

echo "=== Step 3: Install Rancher ==="
if ! helm status rancher -n cattle-system &>/dev/null; then
  helm install rancher rancher-stable/rancher \
    --namespace cattle-system \
    --create-namespace \
    --version "${RANCHER_VERSION}" \
    --set hostname="${RANCHER_HOSTNAME}" \
    --set bootstrapPassword="${RANCHER_BOOTSTRAP_PASSWORD}" \
    --set replicas=1 \
    --wait --timeout 10m
  echo "Rancher v${RANCHER_VERSION} installed"
else
  echo "Rancher already installed, skipping"
fi

echo "=== Step 4: Install rancher-backup operator ==="
if ! helm status rancher-backup -n cattle-resources-system &>/dev/null; then
  helm install rancher-backup rancher-charts/rancher-backup \
    --namespace cattle-resources-system \
    --create-namespace \
    --wait
  echo "rancher-backup operator installed"
else
  echo "rancher-backup already installed, skipping"
fi

echo "=== Step 5: Verify ==="
echo "Waiting for Rancher deployment..."
kubectl rollout status deployment/rancher -n cattle-system --timeout=300s
echo ""
echo "Rancher UI: https://${RANCHER_HOSTNAME}"
echo "Bootstrap password: ${RANCHER_BOOTSTRAP_PASSWORD}"
echo ""
echo "Next steps:"
echo "  1. Access Rancher UI and set permanent admin password"
echo "  2. Add DO cloud credentials (Cluster Management > Cloud Credentials)"
echo "  3. Apply rancher-backup schedule (kubectl apply -f backup-schedule.yaml)"
