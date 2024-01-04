#!/usr/bin/bash

#Install argocd manifest
kubectl get ns argocd > /dev/null 2>&1
if [ "${?}" -eq 0 ]
then
  echo 'argocd is installed'
  exit 1
fi

kubectl create namespace argocd > /dev/null
echo 'namespace argocd have installed'
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml > /dev/null
sleep 10
echo 'argocd have installed'

#Patch argocd-server
# kubectl patch deployments.apps -n argocd argocd-server -p '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","image":"quay.io/argoproj/argocd:v2.9.3","args":["/usr/local/bin/argocd-server","--insecure"]}]}}}}'
kubectl patch deployments.apps -n argocd argocd-server --patch-file=/dev/stdin  <<EOF
spec:
  template:
    spec:
        containers:
        - name: argocd-server
          image: quay.io/argoproj/argocd:v2.9.3
          args:
            - /usr/local/bin/argocd-server
            - --insecure
EOF
 
# Create ingress
kubectl create ingress -n argocd argocd-server-ingress --rule "${ARGOCD_HOST}/*=argocd-server:80"
echo ingress have created

# Get init admin password and update
sleep 60
ADMIN_INIT_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo)
read -p 'Enter new admin password ' NEW_PASS
argocd login argocd.dev.local --username admin --password ${ADMIN_INIT_PASS} --insecure 
argocd account update-password --account admin --current-password  ${ADMIN_INIT_PASS}  --new-password ${NEW_PASS}