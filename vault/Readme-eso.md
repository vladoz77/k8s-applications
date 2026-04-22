# Config secrets with External Secrets Operator and Vault

## Installing Vault

```bash
# Add certificates
k create ns vault
k apply -f certificate.yaml

# Install helm chart
helm install vault hashicorp/vault -f vault-ha-tls-eso.yaml -n vault
```

## Installing External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

## Configuring Vault


Create a KV v2 secrets engine in Vault:

```bash
# Initialize vault-0 with one key
k exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json

# Get unseal key
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)

# Anseal all pods
kubectl exec -n vault vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY

# Get vault root token
VAULT_ROOT_TOKEN=$(jq -r ".root_token" cluster-keys.json)

# Login vault with root token
k exec -n vault vault-0 -- vault login ${VAULT_ROOT_TOKEN} 

# Connect to vault-0 pod
k exec -n vault vault-0 -it -- sh

# Enable KV v2 secrets engine
vault secrets enable -path=secret kv-v2

# Store some secrets
vault kv put secret/production/database \
  username=dbuser \
  password=SecurePassword123 \
  host=postgres.example.com \
  port=5432

vault kv put secret/production/api-keys \
  stripe_key=sk_live_abc123 \
  sendgrid_key=SG.xyz789 \
  datadog_key=dd_api_key_456

# Check secrets
vault kv list /secret/production
```

## Setting Up Vault Authentication

External Secrets Operator supports multiple Vault authentication methods. We'll cover the most common ones.

### Kubernetes Authentication 

Kubernetes auth allows Vault to authenticate service accounts using their JWT tokens.

Enable and configure Kubernetes auth in Vault:

```bash
# Enable Kubernetes auth method
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# Check AUTH method
vault read auth/kubernetes/config
```

Create a Vault policy that allows reading secrets:

```bash
# Create policy
vault policy write external-secrets-policy - <<EOF
path "secret/data/production/*" {
  capabilities = ["read"]
}
path "secret/metadata/production/*" {
  capabilities = ["list", "read"]
}
EOF
```

Create a Vault role that binds to the Kubernetes service account:

```bash
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets-policy \
  ttl=1h
```

Check kubernetes role

```bash
vault read auth/kubernetes/role/external-secrets
```

## Creating SecretStore with Kubernetes Auth

Create a SecretStore that connects to Vault using Kubernetes authentication:

```bash
k apply -f eso/SecretStore.yaml
```

Check secret store connections

```bash

```