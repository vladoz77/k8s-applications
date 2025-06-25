## Get ca certificate from root ca secret 
```bash
k get secrets -n cert-manager ca-secret -o json | jq '.data."ca.crt"' | base64 -di > /tmp/ca.crt
```
## create secret in argocd namespace with ca
```bash
kubectl create ns argocd 
kubectl create secret generic -n argocd ca-certs --from-file=ca.pem=/tmp/ca.crt
```

## Install argocd 
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update 
helm upgrade --install argocd argo/argo-cd -n argocd  -f argocd.yaml
```





