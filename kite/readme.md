1. Add Helm repository

```bash
helm repo add kite https://kite-org.github.io/kite/
helm repo update
```

2. Install chart

```bash
helm install kite kite/kite -n kube-system -f values.yaml -n kube-system 
```

