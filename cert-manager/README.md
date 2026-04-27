> Docs https://cert-manager.io/docs/
> 
# Install cert-manager
```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.2 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

Create self-signed cluster issure

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
```

Create CA cert
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-selfsigned-ca
  namespace: sandbox
spec:
  isCA: true
  commonName: my-selfsigned-ca
  secretName: root-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

Create CA Issure
```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: sandbox
spec:
  ca:
    secretName: root-secret
```

Create cert
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: [certificate-name]
spec:
  secretName: [secret-name]
  dnsNames:
  - "*.[namespace].svc.cluster.local"
  - "*.[namespace]"
  issuerRef:
    name: [issuer-name]
    kind: Issuer
    group: cert-manager.io
```

# Install trust-manager

>[!Note]
>See the [installation guide](https://cert-manager.io/docs/trust/trust-manager/installation/) for instructions on how to install trust-manager.


```bash
helm repo add jetstack https://charts.jetstack.io --force-update
```

```bash
helm upgrade trust-manager jetstack/trust-manager \
  --install \
  --namespace cert-manager \
  --wait
```

## Create CA bundle with our CA

```yaml
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: trust-ca
  namespace: cert-manager
spec:
  sources:
  - useDefaultCAs: true
  - secret:
      name: ca-secret
      key: tls.crt
  target:
    configMap:
      key: "trust-bundle.pem"
```