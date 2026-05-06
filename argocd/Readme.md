# Argo CD в Kubernetes

Этот репозиторий содержит values-файлы и вспомогательные манифесты для установки Argo CD через Helm:
- базовая установка через Ingress: `argocd.yaml`
- установка с SSO (Dex + OIDC): `argocd-sso.yaml`
- установка через Gateway API (HTTPRoute): `argocd-gateway-api.yaml`
- установка через Gateway API + External Secrets Operator + Vault: `argocd-gateway-api-eso.yaml`
- установка Argo CD Image Updater: `argocd-image-updater.yaml`

## Что лежит в репозитории

- `argocd.yaml` - основная конфигурация Argo CD для домена `argocd.dev.local`
- `argocd-sso.yaml` - конфигурация с OIDC через Authentik
- `argocd-gateway-api.yaml` - вариант с `server.httproute` вместо Ingress
- `argocd-gateway-api-eso.yaml` - вариант с `ExternalSecret` для создания `argocd-secret` из Vault
- `argocd-image-updater.yaml` - конфигурация image updater с приватными registry
- `secret-writer.yaml` - legacy Job для старой схемы, где CA копировался в `Secret`
- `install-argocd-cli.sh` - установка CLI `argocd`

## Требования

- Kubernetes-кластер с доступом через `kubectl`
- Helm 3
- cert-manager
- trust-manager
- ConfigMap `trust-ca` с ключом `trust-bundle.pem` в namespace `argocd`
- (опционально) `jq` и `base64`, если вы вручную диагностируете сертификаты

## Быстрый старт (базовая установка)

1. Создать namespace и проверить trust bundle:

```bash
kubectl create namespace argocd
kubectl get configmap trust-ca -n argocd
kubectl get configmap trust-ca -n argocd -o yaml
```

Примечание:
- `trust-ca` публикуется через `trust-manager`
- chart'ы в этом репозитории монтируют CA именно из `ConfigMap`, а не из `Secret`

2. Установить Argo CD из Helm chart:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd.yaml --create-namespace
```

## Установка с SSO (Dex + Authentik)

Подробная пошаговая инструкция: `Readme argocd-sso.md`

Коротко:

1. Убедиться, что `trust-manager` уже опубликовал `ConfigMap trust-ca` в namespace `argocd`:

```bash
kubectl get configmap trust-ca -n argocd
kubectl get configmap trust-ca -n argocd -o yaml
```

2. Установить Argo CD с SSO-конфигом:

```bash
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd-sso.yaml
```

Примечание:
- в `argocd-sso.yaml` нужно заменить `clientID` и `clientSecret` на свои значения
- локальный пользователь `admin` в SSO-схеме отключен через `admin.enabled: false`
- для RBAC в OIDC провайдере нужны группы `ArgoCD Admins` и `ArgoCD Viewers`
- для CLI используйте `argocd login argocd.dev.local --sso --grpc-web`
- `dex` и `repoServer` берут доверенный CA из `ConfigMap trust-ca`

## Вариант с Gateway API

Если используете Gateway API, применяйте values-файл:

```bash
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd-gateway-api.yaml --create-namespace
```

Перед установкой проверьте, что `parentRefs` в `argocd-gateway-api.yaml` соответствуют вашему Gateway.

## Вариант с Gateway API + ESO + Vault

Если хотите, чтобы `argocd-secret` создавался из Vault через External Secrets Operator, используйте:

```bash
helm upgrade --install argocd argo/argo-cd -n argocd -f argocd-gateway-api-eso.yaml --create-namespace
```

Подробная инструкция: [Readme-argocd-eso.md](https://github.com/vladoz77/k8s-applications/blob/main/argocd/Readme-argocd-eso.md)

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
