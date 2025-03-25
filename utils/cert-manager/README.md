https://cert-manager.io/docs/

# Create self-signed cluster issure
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}

# Create CA cert
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

# Create CA Issure 
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: sandbox
spec:
  ca:
    secretName: root-secret

# Create cert
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