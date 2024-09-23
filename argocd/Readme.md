# Get ca certificate from ca secret 
k get secrets -n cert-manager ca-secret -o json | jq '.data."ca.crt"' | base64 -di > /tmp/ca.crt

# create secret in argocd namespace with ca
kubectl create ns argocd 
kubectl create secret generic -n argocd ca-certs --from-file=ca.pem=/tmp/ca.crt

# Install helm
# helm repo add argo https://argoproj.github.io/argo-helm
# helm repo update 
helm upgrade --install argocd argo/argo-cd -n argocd  -f my-argocd-values.yaml

# Install image update
# Add cred to repo for argocd-imge-updater
kubectl create secret docker-registry nexus-secret -n argocd \
 --docker-server=https://docker.home.local \
 --docker-username='admin' \
 --docker-password='!QAZ2wsx'

 # Get repo ca certificate
kubectl create secret generic -n argocd nexus-ca-certs --from-file=nexus-ca.pem=/etc/docker/certs.d/docker.home.local/ca.crt

# Install argocd image-updater
helm upgrade --install argocd-image-update argo/argocd-image-updater -n argocd -f argocd-image-updater.yaml