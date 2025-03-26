1. To access the Vault Helm chart, add the Hashicorp Helm repository.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
```

2. We create certificate with cert-manager and apply him

```bash
k apply -f certificate.yaml
```

3. Install ha vault by helm

```bash
helm install vault hashicorp/vault -f vault-ha-tls.yaml -n vault
```

4. Initialize vault-0 with one key

```bash
k exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
```



