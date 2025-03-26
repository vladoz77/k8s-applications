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

## Set a secret in Vault

1. Start an interactive shell session on the vault-0 pod.
```bash
kubectl exec -n vault -it vault-0 -- /bin/sh
```
2. Login by root token

```bash
vault login 
```

3. Enable kv-v2 secrets at the path internal.

```bash
vault secrets enable -path=internal kv-v2
```

4. Create a secret at path `secret/database` with a `username` and `password`.

```bash
vault kv put secret/database username="db-readonly-username" password="db-secret-password"
```

5. Verify you can read the secret at the path `secret/database/`.

```bash
vault kv get secret/database
```

## Configure Kubernetes authentication
Vault provides a Kubernetes authentication method that enables clients to authenticate with a Kubernetes Service Account token. Kubernetes provides that token to each pod at the time of pod creation.

1. Start an interactive shell session on the vault-0 pod.

```bash
kubectl exec -n vault -it vault-0 -- /bin/sh
```

2. Enable the Kubernetes authentication method.

```bash
vault auth enable kubernetes
```

3. Configure the Kubernetes authentication method to use the location of the Kubernetes API.

```bash
vault write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
```

4. Write out the policy named `secret-app` that enables the read capability for secrets at path `secret/database`

```bash
vault policy write secret-app - <<EOF
path "secret/*" {
   capabilities = ["read"]
}
EOF
```
5. Create a Kubernetes authentication role named `secret-app`.

```bash
vault write auth/kubernetes/role/secret-app \
      bound_service_account_names=secret-sa \
      bound_service_account_namespaces=default \
      policies=secret-app \
      ttl=24h
```

## Define a Kubernetes service account
The Vault Kubernetes authentication role defined a Kubernetes service account named secret-sa.

1. Create a Kubernetes service account named `secret-sa` in the default namespace.

```bash
kubectl create sa secret-sa
```
The name of the service account here aligns with the name assigned to the `bound_service_account_names` field from the internal-app role.


## Launch an application

1. Apply the pod defined in example/devwebapp.yaml.

```bash
k apply -f example/devwebapp.yaml
```
2. Check logs `vault-agent-init` pod and `vault-0` pod

```bash
k logs pods/devwebapp -c vault-agent-init
k logs -n vault pods/vault-0
```

