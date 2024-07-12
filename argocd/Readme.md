# Get ca certificate from ca secret 
k get secrets -n cert-manager ca-secret -o json | jq '.data."ca.crt"' | base64 -di > /tmp/ca.crt

# create secret in argocd namespace with ca
k create ns argocd 
kubectl create secret generic -n argocd ca-certs --from-file=ca.pem=/tmp/ca.crt

# Install helm
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update 
helm upgrade --install argocd argo/argo-cd -n argocd  -f my-argocd-values.yaml