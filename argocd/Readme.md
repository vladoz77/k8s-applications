# Argo CD в Kubernetes

Этот репозиторий содержит values-файлы и вспомогательные манифесты для установки Argo CD через Helm:
- базовая установка через Ingress: `argocd.yaml`
- установка с SSO (Dex + OIDC): `argocd-sso.yaml`
- установка через Gateway API (HTTPRoute): `argocd-gateway-api.yaml`
- установка Argo CD Image Updater: `argocd-image-updater.yaml`

## Что лежит в репозитории

- `argocd.yaml` - основная конфигурация Argo CD для домена `argocd.dev.local`
- `argocd-sso.yaml` - конфигурация с OIDC через Authentik
- `argocd-gateway-api.yaml` - вариант с `server.httproute` вместо Ingress
- `argocd-image-updater.yaml` - конфигурация image updater с приватными registry
- `secret-writer.yaml` - Job, который копирует CA из `cert-manager` в secret `argocd/ca-certs`
- `install-argocd-cli.sh` - установка CLI `argocd`

## Требования

- Kubernetes-кластер с доступом через `kubectl`
- Helm 3
- `jq` и `base64`
- (опционально) cert-manager для выпуска сертификатов (`ClusterIssuer: ca-issuer`)

## Быстрый старт (базовая установка)

1. Создать namespace и secret с корневым CA:

```bash
kubectl create namespace argocd
kubectl get secret -n cert-manager ca-secret -o json | jq -r '.data["ca.crt"]' | base64 -d > /tmp/ca.crt
kubectl create secret generic -n argocd ca-certs --from-file=ca.pem=/tmp/ca.crt
```

2. Установить Argo CD из Helm chart:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd.yaml --create-namespace
```

## Установка с SSO (Dex + Authentik)

1. Подготовить CA для OIDC-провайдера:

```bash
kubectl get secret -n auth authentik-tls -o json | jq -r '.data["ca.crt"]' | base64 -d > /tmp/auth-ca.crt
kubectl create secret generic -n argocd auth-ca-certs --from-file=auth-ca.pem=/tmp/auth-ca.crt
```

2. Установить Argo CD с SSO-конфигом:

```bash
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd-sso.yaml
```

Примечание:
- в `argocd-sso.yaml` заданы `clientID` и `clientSecret`; перед применением замените их на свои значения
- для RBAC в OIDC провайдере нужны группы `ArgoCD Admins` и `ArgoCD Viewers`

## Вариант с Gateway API

Если используете Gateway API, применяйте values-файл:

```bash
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd-gateway-api.yaml --create-namespace
```

Перед установкой проверьте, что `parentRefs` в `argocd-gateway-api.yaml` соответствуют вашему Gateway.

## Argo CD Image Updater

1. Создать pull-secrets для registry:

```bash
kubectl create secret docker-registry nexus-secret -n argocd \
  --docker-server=https://docker.home.local \
  --docker-username='<user>' \
  --docker-password='<password>'

kubectl create secret docker-registry harbor-secret -n argocd \
  --docker-server=https://reg.dev.local \
  --docker-username='<user>' \
  --docker-password='<password>'
```

2. Создать secrets с CA сертификатами:

```bash
kubectl create secret generic -n argocd nexus-ca-certs --from-file=nexus-ca.pem=/path/to/docker.home.local-ca.crt
kubectl create secret generic -n argocd harbor-ca-certs --from-file=harbor-ca.pem=/path/to/reg.dev.local-ca.crt
```

3. Установить image updater:

```bash
helm upgrade --install argocd-image-updater argo/argocd-image-updater -n argocd -f argocd-image-updater.yaml
```

## Установка CLI

```bash
sudo bash ./install-argocd-cli.sh
```





