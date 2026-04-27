# Vault + External Secrets Operator

This guide shows how to:

1. Install Vault in Kubernetes with TLS enabled.
2. Install External Secrets Operator (ESO).
3. Configure Vault KV v2 and Kubernetes authentication.
4. Sync secrets from Vault into Kubernetes `Secret` objects.
5. Use templated and combined `ExternalSecret` patterns in workloads.

## Prerequisites

- A running Kubernetes cluster
- `helm`, `kubectl`, and `jq`
- TLS assets for Vault (`certificate.yaml`)
- Vault Helm values for ESO integration (`vault-ha-tls-eso.yaml`)
- A trusted CA bundle published as ConfigMap `trust-ca` with key `trust-bundle.pem`

## 1. Install Vault

Add the HashiCorp Helm repository:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Create the namespace and apply the TLS certificate resources:

```bash
kubectl create namespace vault
kubectl apply -f certificate.yaml
```

Install Vault:

```bash
helm install vault hashicorp/vault -f vault-ha-tls-eso.yaml -n vault
```

Check that the pods are running:

```bash
kubectl get pods -n vault
```

## 2. Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

Verify the deployment:

```bash
kubectl get pods -n external-secrets
```

## 3. Initialize and unseal Vault

Initialize `vault-0` and save the generated keys locally:

```bash
kubectl exec -n vault vault-0 -- \
  vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
```

Export the unseal key and root token:

```bash
export VAULT_UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' cluster-keys.json)
export VAULT_ROOT_TOKEN=$(jq -r '.root_token' cluster-keys.json)
```

Unseal all Vault pods:

```bash
kubectl exec -n vault vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl exec -n vault vault-1 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl exec -n vault vault-2 -- vault operator unseal "$VAULT_UNSEAL_KEY"
```

Log in to Vault:

```bash
kubectl exec -n vault vault-0 -- vault login "$VAULT_ROOT_TOKEN"
```

Open a shell inside `vault-0` for the next steps:

```bash
kubectl exec -n vault -it vault-0 -- sh
```

## 4. Enable KV v2 and write sample secrets

Enable a KV v2 secrets engine at path `production`:

```bash
vault secrets enable -path=production kv-v2
```

Write example secrets:

```bash
vault kv put production/database \
  username=postgress \
  password=Password \
  host=postgres.home.local \
  port=5432

vault kv put production/api-keys \
  stripe_key=sk_live_abc123 \
  sendgrid_key=SG.xyz789 \
  datadog_key=dd_api_key_456
```

Verify that the secrets exist:

```bash
vault kv get production/database
vault kv list production
```

## 5. Configure Kubernetes authentication in Vault

Enable the Kubernetes auth method:

```bash
vault auth enable kubernetes
```

Configure Vault to trust the cluster service account issuer:

```bash
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

Check the auth configuration:

```bash
vault read auth/kubernetes/config
```

Create a policy that allows ESO to read KV v2 secrets from the `production` engine:

```bash
vault policy write production-policy - <<'EOF'
path "production/data/*" {
  capabilities = ["read"]
}

path "production/metadata/*" {
  capabilities = ["list", "read"]
}
EOF
```

Create the Vault role used by the Kubernetes service account:

```bash
vault write auth/kubernetes/role/production-secrets \
  bound_service_account_names=production-sa \
  bound_service_account_namespaces=production \
  policies=production-policy \
  ttl=1h
```

Verify the role:

```bash
vault read auth/kubernetes/role/production-secrets
```

## 6. Create the SecretStore

Create manifest `vim eso/SecretStore-production.yaml`

```yaml
# SecretStore-production.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: production-sa
  namespace: production

---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-backend-production
  namespace: production
spec:
  provider:
    vault:
      server: "https://vault.vault.svc.cluster.local:8200"
      path: production
      version: "v2"
      caProvider:
        type: ConfigMap
        name: trust-ca
        key: trust-bundle.pem
      auth:
        kubernetes:
          mountPath: kubernetes
          role: production-secrets
          serviceAccountRef:
            name: production-sa
```

Apply the namespace, service account, and `SecretStore`:

```bash
kubectl apply -f eso/SecretStore-production.yaml
```

Check:

```bash
kubectl describe secretstores.external-secrets.io vault-backend-production -n production
```

## 7. ExternalSecret manifests

### `eso/ExternelSecret-database.yaml`

This manifest creates the Kubernetes secret `database-credentials` from individual fields stored in Vault at `production/database`.

Create manifest `vim eso/ExternelSecret-database.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: production
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend-production
    kind: SecretStore
  target:
    name: database-credentials
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: database
      property: username
  - secretKey: password
    remoteRef:
      key: database
      property: password
  - secretKey: host
    remoteRef:
      key: database
      property: host
  - secretKey: port
    remoteRef:
      key: database
      property: port
```

Apply manifest:

```bash
kubectl apply -f eso/ExternelSecret-database.yaml
```

Check:

```bash
kubectl describe externalsecrets.external-secrets.io database-credentials -n production
kubectl get secret database-credentials -n production -o yaml
```

### `eso/ExternelSecret-ALL.yaml`

This manifest creates the Kubernetes secret `api-keys` and imports all fields from Vault path `production/api-keys` by using `dataFrom.extract`.

Create manifest `vim eso/ExternelSecret-ALL.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: api-keys
  namespace: production
spec:
  refreshInterval: 10m
  secretStoreRef:
    name: vault-backend-production
    kind: SecretStore
  target:
    name: api-keys
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: api-keys
```

Apply manifest:

```bash
kubectl apply -f eso/ExternelSecret-ALL.yaml
```

Check:

```bash
kubectl describe externalsecrets.external-secrets.io api-keys -n production
kubectl get secret api-keys -n production -o yaml
```

### `eso/externel_secret_template.yaml`

This manifest creates the Kubernetes secret `database-connection` and uses `target.template` to build derived values from Vault data:

- `connection_string` is rendered from `username`, `password`, `host`, and `port`
- `config.json` is rendered as an application config file

This is useful when the application needs a ready-to-use connection string or config artifact instead of raw secret fields.

Create manifest `vim eso/externel_secret_template.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-connection
  namespace: production
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend-production
    kind: SecretStore
  target:
    name: database-connection
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # Create connection string
        connection_string: |
          postgresql://{{ .username }}:{{ .password }}@{{ .host }}:{{ .port }}/production
        # Create JSON config
        config.json: |
          {
            "database": {
              "host": "{{ .host }}",
              "port": {{ .port }},
              "username": "{{ .username }}",
              "password": "{{ .password }}",
              "ssl": true
            }
          }
  data:
  - secretKey: username
    remoteRef:
      key: database
      property: username
  - secretKey: password
    remoteRef:
      key: database
      property: password
  - secretKey: host
    remoteRef:
      key: database
      property: host
  - secretKey: port
    remoteRef:
      key: database
      property: port
```

Apply manifest:

```bash
kubectl apply -f eso/externel_secret_template.yaml
```

Check:

```bash
kubectl describe externalsecrets.external-secrets.io database-connection -n production
kubectl get secret database-connection -n production -o yaml
```

### `eso/externel_secret_combined.yaml`

This manifest creates the Kubernetes secret `app-config` and combines values from different Vault secrets into one Kubernetes secret:

- `db_password` comes from `production/database`
- `stripe_key` comes from `production/api-keys`

This pattern is useful when one workload expects a single Kubernetes `Secret`, but the source values are stored in separate Vault paths.

Create manifest `vim eso/externel_secret_combined.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-config
  namespace: production
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: vault-backend-production
    kind: SecretStore
  target:
    name: app-config
    creationPolicy: Owner
  data:
  # From database secret
  - secretKey: db_password
    remoteRef:
      key: database
      property: password
  # From API keys
  - secretKey: stripe_key
    remoteRef:
      key: api-keys
      property: stripe_key
```

Apply manifest:

```bash
kubectl apply -f eso/externel_secret_combined.yaml
```

Check:

```bash
kubectl describe externalsecrets.external-secrets.io app-config -n production
kubectl get secret app-config -n production -o yaml
```

## 8. Test deployment with generated secret

This deployment reads `connection_string` from secret `database-connection` into environment variable `pg_connections` and mounts `config.json` into the container at `/app/config.json`.

Create manifest `vim eso/test-secret.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: test-secret
  name: test-secret
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-secret
  template:
    metadata:
      labels:
        app: test-secret
    spec:
      containers:
      - image: nginx
        name: nginx
        resources: {}
        env:
        - name: pg_connections
          valueFrom:
            secretKeyRef:
              name: database-connection
              key: connection_string
        volumeMounts:
        - name: db-config
          mountPath: /app/config.json
          subPath: config.json
          readOnly: true
      volumes:
      - name: db-config
        secret:
          secretName: database-connection
```

Apply manifest:

```bash
kubectl apply -f eso/test-secret.yaml
```

Check:

```bash
kubectl get deploy,pod -n production
kubectl describe deployment test-secret -n production
kubectl exec -n production deploy/test-secret -- printenv pg_connections
kubectl exec -n production deploy/test-secret -- cat /app/config.json
```

## Files used in this flow

- `vault-ha-tls-eso.yaml`
- `certificate.yaml`
- `eso/SecretStore-production.yaml`
- `eso/ExternelSecret-database.yaml`
- `eso/ExternelSecret-ALL.yaml`
- `eso/externel_secret_template.yaml`
- `eso/externel_secret_combined.yaml`
- `eso/test-secret.yaml`

## Notes

- `SecretStore-production.yaml` uses Vault path `production` with KV version `v2`.
- The policy must use KV v2 API paths: `production/data/*` and `production/metadata/*`.
- The `trust-ca` ConfigMap must exist in the same namespace as the `SecretStore` (`production`).
- For `data` and `dataFrom.extract`, secret keys are resolved relative to the store path. With `path: production`, use `database` or `api-keys`, not `production/database`.
- In `target.template`, ESO template variables such as `{{ .username }}` come from the keys declared in the `data` section.
- `eso/test-secret.yaml` depends on secret `database-connection`, so apply `eso/externel_secret_template.yaml` first.
