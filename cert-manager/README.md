> Docs https://cert-manager.io/docs/
> 
0. Install cert-manager
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml
```
1. Create self-signed cluster issure
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
```

2. Create CA cert
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

3. Create CA Issure
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

4. Create cert
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
