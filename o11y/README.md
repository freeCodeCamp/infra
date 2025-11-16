# Observability Stack Setup

This document outlines the steps to set up an observability stack using Loki,
Prometheus, and Grafana.

## 1. Prerequisites & Initial Setup

1.  **Kubernetes Cluster Setup (DigitalOcean k8s)**

    1.  Create Cluster: Use `doctl` (adjust name, region, node pool as needed):
        ```bash
        doctl kubernetes cluster create o11y-cluster --region nyc3 --node-pool "name=o11y-compute;count=3;size=s-4vcpu-8gb"
        ```
    2.  Configure `kubectl`: `doctl` automatically saves the cluster's
        kubeconfig (usually to `~/.kube/config`) and sets the current context.
        Ensure your `kubectl` context points to the new cluster. If needed, copy
        relevant config to a local `./.kubeconfig.yaml` and set
        `export KUBECONFIG=./.kubeconfig.yaml`.

2.  **Object Storage for Loki (DigitalOcean Spaces)**

    1.  Create Space: Manually create a DigitalOcean Space named
        `net.freecodecamp.o11y.01` in your desired region.
    2.  Generate Keys: In the DigitalOcean Control Panel (API -> Spaces access
        keys), generate a new access key and secret key for this Space. These
        will be used in the secrets configuration later.

3.  **Working Directory** Locate and change to the `o11y` directory for
    subsequent commands:
    ```bash
    cd o11y
    ```

## 2. Helm Repositories

Install and update necessary Helm chart repositories:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

## 3. Core Infrastructure Installation

1.  **Namespace Creation** Create the `o11y` namespace for our observability
    components:

    ```bash
    kubectl create namespace o11y
    ```

2.  **Secrets Configuration & Creation (via Kustomize)**

    1.  Prepare Secret Files:
        - Create and populate `.secrets.env` in `k8s/base/secrets/` based on
          `.secrets.env.example`. (Do NOT use quotes around values).
        - Place your Cloudflare origin certificate into
          `k8s/base/secrets/tls.crt`.
        - Place your Cloudflare private key into `k8s/base/secrets/tls.key`.
    2.  Apply Kustomized Secrets:
        ```bash
        kubectl apply -k k8s/base/
        ```
        > Note: The `o11y-secrets` Kubernetes secret will be used by Loki and
        > Grafana.

3.  **Metrics Server** _Install:_

    ```bash
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    ```

    _Verify:_

    ```bash
    kubectl get deployment metrics-server -n kube-system
    ```

4.  **NGINX Ingress Controller** _Create Namespace (if not present, though
    usually handled by Helm):_
    ```bash
    kubectl create namespace ingress-nginx # Optional, Helm might create it
    ```
    _Install:_
    ```bash
    helm upgrade ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --install -f charts/ingress-nginx/values.yaml
    ```
    _Verify:_
    ```bash
    kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
    ```

## 4. Observability Stack Deployment

1.  **Loki Deployment (Log Aggregation)** _Install:_

    ```bash
    helm upgrade loki grafana/loki --namespace o11y --install -f charts/loki/values.yaml
    ```

    _Verify:_

    ```bash
    kubectl get pods -n o11y -l app.kubernetes.io/name=loki
    ```

2.  **Prometheus Stack Installation (Metrics Collection)**

    1.  Install `kube-prometheus-stack`: The stack is configured via
        `charts/prometheus/values.yaml`. This configuration disables the Grafana
        instance included with the stack (as we use a separate one) and sets
        conservative resource limits.
        ```bash
        helm upgrade prometheus prometheus-community/kube-prometheus-stack --namespace o11y --install --create-namespace -f charts/prometheus/values.yaml
        ```
    2.  Verify Installation:
        ```bash
        kubectl --namespace o11y get pods -l "release=prometheus"
        ```
        Allow a few minutes for all pods to become ready.

3.  **Grafana Deployment (Visualization)** _Install:_
    ```bash
    helm upgrade grafana grafana/grafana --namespace o11y --install -f charts/grafana/values.yaml
    ```
    _Verify:_
    ```bash
    kubectl get pods -n o11y -l app.kubernetes.io/name=grafana
    ```
    _Data Sources Note:_ The Grafana configuration in
    `charts/grafana/values.yaml` automatically provisions:
    - **Loki** datasource, pointing to
      `http://loki-gateway.o11y.svc.cluster.local`.
    - **Prometheus** datasource, pointing to
      `http://prometheus-kube-prometheus-prometheus.o11y.svc.cluster.local:9090`.
      You can import dashboards like
      [Kubernetes cluster monitoring (via Prometheus) - ID 315](https://grafana.com/grafana/dashboards/315-kubernetes-cluster-monitoring-via-prometheus/)
      or create your own.

## 5. Ingress & DNS Configuration

1.  **Ingress Configuration (Grafana/Loki)** _Apply:_

    ```bash
    kubectl apply -f k8s/ingress/o11y-ingress.yaml -n o11y
    ```

    _Verify:_

    ```bash
    kubectl get ingress -n o11y
    ```

2.  **DNS Configuration (Manual)**
    1.  Get Load Balancer IP for the NGINX Ingress controller:
        ```bash
        kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | cat
        ```
    2.  Create an A record in Cloudflare for `o11y.freecodecamp.net` pointing to
        the retrieved IP.

## 6. Final Verification

1.  Access Grafana UI via `https://o11y.freecodecamp.net/grafana`.
2.  Confirm Loki and Prometheus datasources are connected in Grafana
    (Connections -> Data Sources).
3.  Test Loki API access (get credentials from `o11y-secrets`):
    ```bash
    export LOKI_GW_PASSWORD=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_GATEWAY_PASSWORD}' | base64 --decode)
    export LOKI_TENANT_ID=$(kubectl get secret o11y-secrets -n o11y -o jsonpath='{.data.LOKI_TENANT_ID}' | base64 --decode)
    # Query Loki logs
    curl -s -u "loki:${LOKI_GW_PASSWORD}" -G "https://o11y.freecodecamp.net/loki/api/v1/query_range" --data-urlencode 'query={job="test"}' -H "X-Scope-OrgID: ${LOKI_TENANT_ID}" | jq
    # Push a test log entry
    curl -H "Content-Type: application/json" -XPOST -s "https://o11y.freecodecamp.net/loki/api/v1/push" --data-raw "{\"streams\": [{\"stream\": {\"job\": \"test\"}, \"values\": [[\"$(date +%s)000000000\", \"Test log entry\"]]}]}" -u "loki:${LOKI_GW_PASSWORD}" -H "X-Scope-OrgID: ${LOKI_TENANT_ID}"
    ```
4.  Verify metrics are flowing into Prometheus by exploring metrics in Grafana
    or using the imported dashboard.

## 7. Grafana Dashboards

Dashboards are managed as TypeScript code in `dashboards/`, providing type-safe, version-controlled dashboard definitions.

### Quick Start

```bash
cd dashboards
pnpm install
pnpm run build
```

Generates:
- `output/api-monitoring.json` - Dashboard JSON
- `../k8s/grafana/dashboards/api-monitoring.yaml` - Kubernetes ConfigMap

### Deploy

```bash
kubectl apply -f ../k8s/grafana/dashboards/api-monitoring.yaml
```

Dashboard auto-loads in Grafana within ~30 seconds.
**Dashboard UID**: `fcc-api-observability-v1-0`

### Development Commands

- **Build**: `pnpm run build`
- **Test**: `pnpm test`
- **Lint**: `pnpm run lint`
- **Validate**: `pnpm run validate`

### Project Structure

- `src/dashboards/` - Dashboard definitions
- `src/builders/` - Reusable query/panel builders
- `tests/` - Unit tests

### Adding Panels

1. Edit `src/dashboards/api-monitoring.ts`
2. Run `pnpm run build`
3. Deploy: `kubectl apply -f ../k8s/grafana/dashboards/api-monitoring.yaml`
