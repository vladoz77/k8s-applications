1. Add harbor repo
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

2. Install harbor
```bash
helm install harbor bitnami/harbor -f harbor.yaml -n harbor
```
