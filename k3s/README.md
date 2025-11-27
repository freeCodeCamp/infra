# k3s Stack (Self-hosted)

Internal tools deployed on self-hosted k3s cluster.

## Structure

```
k3s/
├── apps/
│   └── appsmith/           # Appsmith application
│       └── manifests/
├── cluster/
│   └── charts/
│       └── traefik/        # Shared ingress controller
└── .kubeconfig.yaml
```

## Deploy

```bash
cd k3s    # direnv auto-loads KUBECONFIG

# Cluster setup (one-time)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
helm upgrade traefik traefik/traefik --namespace traefik --create-namespace --install -f cluster/charts/traefik/values.yaml

# Appsmith
kubectl apply -k apps/appsmith/manifests/base/
kubectl apply -f apps/appsmith/manifests/gateway/
kubectl apply -f apps/appsmith/manifests/deployment.yaml
kubectl apply -f apps/appsmith/manifests/service.yaml
kubectl apply -f apps/appsmith/manifests/pvc.yaml
```

## Verify

```bash
kubectl get nodes -o wide
kubectl get gateway -n appsmith
curl -I https://appsmith.freecodecamp.net
```

## Adding New Apps

1. Create `apps/<app-name>/manifests/`
2. Add base (namespace, secrets), gateway (httproutes), and app manifests
3. Follow same deploy pattern
