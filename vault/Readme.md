To access the Vault Helm chart, add the Hashicorp Helm repository.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
```

We create certificate with cert-manager and apply him

```bash
k apply -f certificate.yaml
```

Install ha vault by helm


Initialize vault-0 with one key

```bash
k exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1
```

