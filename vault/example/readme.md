## Set a secret in Vault

1. Login by root token

```bash
vault login 
```

2. Enable kv-v2 secrets at the path `kubernetes/`.

```bash
vault secrets enable -path kubernetes/ kv-v2
```

3. Create a secret at path `kubernetes/postgres` with a username as `postgres` and password - `password`.

```bash
vault kv put kubernetes/postgres username="postgres" password="password"
```

## Configure Kubernetes authentication

Vault provides a Kubernetes authentication method that enables clients to authenticate with a Kubernetes Service Account token. Kubernetes provides that token to each pod at the time of pod creation.

1. Enable the Kubernetes authentication method.

```bash
vault auth enable kubernetes
```

2. Configure the Kubernetes authentication method to use the location of the Kubernetes API.

```bash
vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc.cluster.local:443"
```

3. Write out the policy named `postgres-policy` that enables the read capability for secrets at path `kubernetes/postgres`

```bash
vault policy write postgres-policy - <<EOF
path "kubernetes/postgres*" {
   capabilities = ["read"]
}
EOF
```

4. Create a Kubernetes authentication role named `postgres-role`.

```bash
vault write auth/kubernetes/role/postgres-role \
      bound_service_account_names=postgres-sa \
      bound_service_account_namespaces=db \
      policies=postgres-policy \
      ttl=24h
```

## Define a Kubernetes service account

The Vault Kubernetes authentication role defined a Kubernetes service account named secret-sa.

1. Create a Kubernetes service account named `postgres-sa` in the `db` namespace.

```bash
k create ns db
k create serviceaccount -n db postgres-sa
```

2. Install the secrets store CSI driver

Add repo 

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
```

Install chart

```bash
helm install csi secrets-store-csi-driver/secrets-store-csi-driver \
    --set syncSecret.enabled=true
```

3. Define a SecretProviderClass resource

Define a SecretProviderClass named `vault-postgres-secret`.

```bash
cat > spc-ault-postgres-secret.yaml <<EOF61
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-postgres-secret
spec:
  provider: vault
  secretObjects:
  - data:
    - key: password
      objectName: db-password
    - key: username
      objectName: db-username
    secretName: db-secret
    type: Opaque
  parameters:
    vaultAddress: "https://vault.vault.svc.cluster.local:8200"
    roleName: "postgres-role"
    vaultSkipTLSVerify: "true"
    objects: |
      - objectName: "db-password"
        secretPath: "kubernetes/data/postgres"
        secretKey: "password"
      - objectName: "db-username"
        secretPath: "kubernetes/data/postgres"
        secretKey: "username"
EOF
```

5. Next, update the statefullset to reference the new secret:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-sts
spec:
  selector:
    matchLabels:
      app: postgresql-app
  serviceName: postgresql-svc-headless
  replicas: 1
  template:
    metadata:
      labels:
        app: postgresql-app
    spec:
      serviceAccount: postgres-sa
      containers:
      - name: postgresql
        image: postgres:16.2
        env:
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        resources: {}
        ports:
        - containerPort: 5432
          name: psql
        volumeMounts:
        - name: db
          mountPath: /var/lib/postgresql/data
        - name: secrets-store-inline
          mountPath: "/mnt/secrets-store"
          readOnly: true
      volumes:
      - name: secrets-store-inline
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "vault-postgres-secret"
  volumeClaimTemplates:
  - metadata:
      name: db
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: longhorn-db
      resources:
        requests:
          storage: 5Gi
```