# Argo CD + authentik через Helm chart

Инструкция описывает интеграцию `Argo CD` и `authentik` через `Dex`, если Argo CD устанавливается chart'ом `argo/argo-cd`.

Почему здесь используется `Dex`, а не `oidc`:
- `Dex` позволяет входить и в Web UI, и через `argocd` CLI
- при прямой `oidc` конфигурации CLI обычно не работает так удобно

В этом репозитории для сценария SSO используется файл `argocd-sso.yaml`.

## Что получится

- `Argo CD` будет доступен по адресу `https://argocd.dev.local`
- `authentik` будет доступен по адресу `https://auth.dev.local`
- вход в Argo CD будет выполняться через `authentik`
- права в Argo CD будут назначаться по группам из `authentik`

## Требования

- установлен Kubernetes-кластер
- установлен `Helm`
- установлен `kubectl`
- установлен `cert-manager`
- установлен `trust-manager`
- DNS или `/etc/hosts` должны резолвить:
  - `argocd.dev.local`
  - `auth.dev.local`
- должен существовать Gateway `envoy-gateway` в namespace `envoy-gateway-system`, если вы используете `HTTPRoute`
- `trust-manager` должен публиковать `ConfigMap trust-ca` с ключом `trust-bundle.pem` в namespace `argocd`

## 1. Установка authentik

Добавьте Helm-репозиторий:

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update
```

Пример values для `authentik`:

```yaml
fullnameOverride: authentik

global:
  nameOverride: authentik
  namespaceOverride: auth
  addPrometheusAnnotations: true
  image:
    repository: ghcr.io/goauthentik/server
    pullPolicy: IfNotPresent

authentik:
  log_level: info
  secret_key: "<replace-me>"
  email:
    host: smtp.gmail.com
    port: 465
    username: "<smtp-user>"
    password: "<smtp-password>"
    use_ssl: true
    from: authentik@example.com
  postgresql:
    password: "<replace-me>"

server:
  replicas: 1
  metrics:
    enabled: true
  route:
    main:
      enabled: true
      https: true
      hostnames:
        - auth.dev.local
      parentRefs:
        - name: envoy-gateway
          namespace: envoy-gateway-system
          sectionName: https
          port: 443

postgresql:
  enabled: true
  auth:
    password: "<replace-me>"
```

Установка:

```bash
helm upgrade --install authentik authentik/authentik \
  -n auth \
  --create-namespace \
  -f values.yaml
```

После установки откройте:

```text
https://auth.dev.local/if/flow/initial-setup/
```

## 2. Настройка authentik

### Создать OAuth2/OpenID Provider

В `authentik` откройте `Applications -> Providers` и создайте провайдер типа `OAuth2/OpenID Provider` со следующими параметрами:

- `Name`: `ArgoCD`
- `Client Type`: `Confidential`
- `Signing Key`: любой доступный ключ
- `Redirect URIs`:

```text
https://argocd.dev.local/api/dex/callback
http://localhost:8085/auth/callback
```

После создания сохраните:

- `Client ID`
- `Client Secret`

Они понадобятся в `argocd-sso.yaml`.

### Создать Application

В `Applications -> Applications` создайте приложение:

- `Name`: `ArgoCD`
- `Provider`: `ArgoCD`
- `Slug`: `argocd`
- `Launch URL`: `https://argocd.dev.local/auth/login`

### Создать группы

Создайте группы, которые потом будут использованы в `Argo CD RBAC`:

- `ArgoCD Admins`
- `ArgoCD Viewers`

Важно:
- имена групп в `authentik` должны совпадать с именами в `policy.csv`
- пользователи получают права в Argo CD именно через эти группы

## 3. Подготовка доверенных сертификатов для Argo CD

В вашей схеме сертификаты выпускает `cert-manager`, а `trust-manager` публикует доверенный CA bundle в `ConfigMap`.

Для Argo CD здесь используется единый источник доверия:

- `ConfigMap`: `trust-ca`
- ключ: `trust-bundle.pem`
- namespace: `argocd`

Этот bundle используется:

- `dex` для TLS-доверия к `authentik`
- `repoServer` для TLS-доверия к внутренним Git/Helm endpoints

Сначала убедитесь, что namespace существует:

```bash
kubectl create namespace argocd
```

Затем проверьте, что `trust-manager` уже опубликовал bundle:

```bash
kubectl get configmap trust-ca -n argocd
kubectl get configmap trust-ca -n argocd -o yaml
```

Внутри должен быть ключ `trust-bundle.pem`.

Если нужно показать, как формируется bundle, пример ресурса `Bundle` выглядит так:

```yaml
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: trust-ca
spec:
  sources:
    - secret:
        name: ca-secret
        key: tls.crt
  target:
    configMap:
      key: trust-bundle.pem
```

Вручную создавать `Secret ca-certs` или отдельный `ConfigMap` для `authentik` в этой схеме не нужно.

## 4. Настройка Argo CD

Основная идея:

- `Dex` подключается к `authentik` как к OIDC provider
- локальный пользователь `admin` отключен
- `clientSecret` хранится в `configs.secret.extra`
- RBAC назначается через группы `ArgoCD Admins` и `ArgoCD Viewers`
- внешний доступ публикуется через `HTTPRoute`

Пример содержимого `argocd-sso.yaml`:

```yaml
nameOverride: argocd
fullnameOverride: argocd

crds:
  keep: true

global:
  domain: argocd.dev.local
  logging:
    format: json
    level: info

configs:
  cm:
    admin.enabled: false
    url: https://argocd.dev.local
    application.resourceTrackingMethod: annotation
    controller.diff.server.side: "true"
    dex.config: |
      connectors:
      - config:
          issuer: https://auth.dev.local/application/o/argocd/
          clientID: <client-id-from-authentik>
          clientSecret: $dex.authentik.clientSecret
          insecureEnableGroups: true
          scopes:
            - openid
            - profile
            - email
        name: authentik
        type: oidc
        id: authentik
  params:
    server.insecure: true
  secret:
    extra:
      dex.authentik.clientSecret: "<client-secret-from-authentik>"
  rbac:
    create: true
    policy.csv: |
      g, ArgoCD Admins, role:admin
      g, ArgoCD Viewers, role:readonly

dex:
  image:
    tag: v2.45.1
  volumes:
    - name: trust-ca
      configMap:
        name: trust-ca
  volumeMounts:
    - mountPath: /etc/ssl/certs/trust-bundle.pem
      name: trust-ca
      subPath: trust-bundle.pem
      readOnly: true

server:
  httproute:
    enabled: true
    parentRefs:
      - name: envoy-gateway
        namespace: envoy-gateway-system
        sectionName: https
        port: 443
    hostnames:
      - argocd.dev.local

repoServer:
  volumes:
    - name: trust-ca
      configMap:
        name: trust-ca
  volumeMounts:
    - mountPath: /etc/ssl/certs/ca.pem
      name: trust-ca
      subPath: trust-bundle.pem
      readOnly: true
```

Важно:
- замените `clientID` и `dex.authentik.clientSecret` на свои значения
- не храните реальные секреты в Git
- `admin.enabled: false` отключает локального пользователя `admin`
- после этого вход в Argo CD останется только через OIDC
- перед применением проверьте, что ваш пользователь входит в группу `ArgoCD Admins`, иначе можно потерять административный доступ

## 5. Установка Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f argocd-sso.yaml
```

## 6. Проверка

Проверьте ресурсы:

```bash
kubectl get pods -n argocd
kubectl get httproute -n argocd
kubectl get configmap trust-ca -n argocd
```

Откройте:

```text
https://argocd.dev.local
```

В интерфейсе должна появиться кнопка входа через `authentik`.

Локальный вход пользователем `admin` в этой схеме не используется.

Проверка CLI:

```bash
argocd login argocd.dev.local --sso --grpc-web
```

## 7. Диагностика

Если SSO не работает, проверьте:

- `Redirect URI` в `authentik` совпадает с `https://argocd.dev.local/api/dex/callback`
- `clientID` и `clientSecret` перенесены без ошибок
- `issuer` указывает на `https://auth.dev.local/application/o/argocd/`
- `ConfigMap trust-ca` существует в namespace `argocd`
- в `trust-ca` есть ключ `trust-bundle.pem`
- `dex` и `repoServer` действительно смонтировали `trust-ca`
- в `argocd-cm` установлено `admin.enabled: false`
- группы `ArgoCD Admins` и `ArgoCD Viewers` существуют в `authentik`
- пользователь действительно состоит в нужной группе

Полезные команды:

```bash
kubectl logs -n argocd deploy/argocd-server
kubectl logs -n argocd deploy/argocd-dex-server
kubectl get cm argocd-cm -n argocd -o yaml
kubectl get secret argocd-secret -n argocd -o yaml
```
