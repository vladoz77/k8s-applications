## Install image update
### Add cred to repo for argocd-imge-updater
```bash
kubectl create secret docker-registry harbor-secret -n argocd \
 --docker-server=https://reg.dev.local \
 --docker-username='argocd' \
 --docker-password='!QAZ2wsx'
 ```

### Get repo ca certificate
```bash
kubectl create secret generic -n argocd harbor-ca-certs --from-file=nexus-ca.pem=/etc/docker/certs.d/reg.dev.local/ca.crt
```

### Install argocd image-updater
```bash
helm upgrade --install argocd-image-update argo/argocd-image-updater -n argocd -f argocd-image-updater.yaml
```