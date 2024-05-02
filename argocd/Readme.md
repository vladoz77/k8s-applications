# Get ca certificate from ca secret 
k get secrets -n cert-manager ca-secret -o json | jq '.data."ca.crt"' | base64 -di > ca.crt

# create secret in argocd namespace with ca
kubectl create secret generic -n argo-cd ca-certs --from-file=ca.pem=ca.crt

# Install helm
helm upgrade --install argocd argo/argo-cd -n argocd  -f my-argocd-values.yaml