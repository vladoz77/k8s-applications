1. Add harbor repo
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

2. Install harbor
```bash
helm upgrade --install -n harbor harbor bitnami/harbor -f harbor.yaml 
```
