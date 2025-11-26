# Tools K3s Stack

## Deploy

```bash
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
kubectl apply -f charts/traefik/values.yaml
kubectl apply -k k8s/base/
kubectl apply -f k8s/gateway/
kubectl apply -f k8s/appsmith/
```

## Verify

```bash
kubectl get nodes -o wide
kubectl get gateway -n appsmith
curl -I https://appsmith.freecodecamp.net
```
