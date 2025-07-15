## Install Vault with csi provider

0. Create ceritificate file with cert-manager

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-cert
  namespace: vault
spec:
  duration: 2160h # 90d
  renewBefore: 360h # 15d
  subject:
    organizations:
    - home
  secretName: vault-tls
  dnsNames:
  - "*.dev.local"
  - "*.vault.svc"
  - "*.vault.svc.cluster.local"
  - "*.vault-internal"
  - vault
  ipAddresses:
  - 127.0.0.1
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

1. Add repo hashicorp

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
```

2. Create values file `vault-single-tls.yaml` for vault and csi provider

```yaml
global:
  enabled: true
  tlsDisable: false
  namespace: vault
injector:
  enabled: false
  metrics:
    enabled: true
  logLevel: info
  logFormat: "json"
csi:
  enabled: true
  metrics:
    enabled: true
  logLevel: info
  logFormat: "json"
  volumes:
  - name: vault-ha-tls
    secret:
      defaultMode: 420
      secretName: vault-tls
  volumeMounts:
  - mountPath: /etc/ssl/certs
    name: vault-ha-tls
    readOnly: true
server:
  image:
    repository: "hashicorp/vault"
    tag: "1.18.1"
  logLevel: info
  logFormat: json
  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 256Mi
      cpu: 250m
  extraEnvironmentVars:
    VAULT_CACERT: /vault/userconfig/vault-ha-tls/ca.crt
    VAULT_TLSCERT: /vault/userconfig/vault-ha-tls/tls.crt
    VAULT_TLSKEY: /vault/userconfig/vault-ha-tls/tls.key
  volumes:
  - name: vault-ha-tls
    secret:
      defaultMode: 420
      secretName: vault-tls
  volumeMounts:
  - mountPath: /vault/userconfig/vault-ha-tls
    name: vault-ha-tls
    readOnly: true
  standalone:
    enabled: true
    config: |-
      cluster_name = "vault"
      ui = true
      listener "tcp" {
        tls_disable = 0
        address = "[::]:8200"
        cluster_address = "[::]:8201"
        tls_cert_file = "/vault/userconfig/vault-ha-tls/tls.crt"
        tls_key_file  = "/vault/userconfig/vault-ha-tls/tls.key"
        tls_client_ca_file = "/vault/userconfig/vault-ha-tls/ca.crt"
      }

      storage "raft" {
        path = "/vault/data"
      }

      telemetry {
        prometheus_retention_time = "30s"
        disable_hostname = true
      }
  ha:
    enabled: false
  affinity: ""
  dataStorage:
    enabled: true
    size: 10Gi
    mountPath: "/vault/data"
    storageClass: local-path
    accessMode: ReadWriteOnce
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: ca-issuer
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    ingressClassName: nginx
    hosts:
    - host: vault.dev.local
    tls:
    - secretName: vault-ui-tls
      hosts:
      - vault.dev.local
```

3. Install helm chart

```bash
helm upgrade --install  vault vault -f vault-single-tls.yaml -n vault
```

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
vault write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
```

3. Write out the policy named `postgres-policy` that enables the read capability for secrets at path `kubernetes/postgres`

```bash
vault policy write postgres-policy - <<EOF
path "kubernetes/data/postgres" {
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
    --set syncSecret.enabled=true \
    --set enableSecretRotation=true \
    --set rotationPollInterval=30s \
    -n vault
```

3. Define a SecretProviderClass resource

Define a SecretProviderClass named `vault-postgres-secret`.

```bash
cat > spc-ault-postgres-secret.yaml <<EOF
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

5. Next, create the statefullset for our bd:

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
      storageClassName: local-path
      resources:
        requests:
          storage: 5Gi
```