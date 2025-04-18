## Install vault ha cluster

1. To access the Vault Helm chart, add the Hashicorp Helm repository.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
```

2. Create ns `vault` 

```bash
k create ns vault
```

3. We create certificate with cert-manager and apply him

```bash
k apply -f certificate.yaml
```

3. Install ha vault by helm

We can pull chart localy

```bash
helm pull hashicorp/vault
tar -xvf vault-0.29.1.tgz
rm -rf vault-0.29.1.tgz
```
Install chart with values

```bash
helm install vault vault -f vault-ha-tls.yaml -n vault
```

You can check vault pod with

```bash
k get all -n vault
```

4. Initialize vault-0 with one key

```bash
k exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
```

5. Display the unseal key found in cluster-keys.json.

```bash
jq -r ".unseal_keys_b64[]" cluster-keys.json
```

6. Create a variable named `VAULT_UNSEAL_KEY` to capture the Vault unseal key.

```bash
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
```

1. Unseal all Vault pods.

```bash
kubectl exec -n vault vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

