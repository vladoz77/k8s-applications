## Install adapter

Add repo
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Install helm chart
```bash
helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter -f prometheus-adapter/prometheus-adapter.yaml -n monitoring
```
Check metrics
```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq .
```


