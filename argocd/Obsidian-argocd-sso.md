---
tags:
  - argocd
  - authentik
  - cert-manager
  - trust-manager
  - kubernetes
---

# Argo CD + Authentik + self-signed CA через cert-manager и trust-manager

> [!info] Что получится
> - `Argo CD` будет доступен по адресу `https://argocd.dev.local`
> - `authentik` будет доступен по адресу `https://auth.dev.local`
> - вход в `Argo CD` будет выполняться через `authentik`
> - TLS будет выпущен от собственного `Root CA`
> - доверие к этому `Root CA` будет распространяться через `trust-manager`

> [!note] Почему здесь используется `Dex`, а не прямой `oidc`
> `Dex` удобен тем, что с ним обычно работают и Web UI, и `argocd` CLI. При прямой `oidc` конфигурации сценарий с CLI часто оказывается менее удобным.

## Исходные данные

В этом репозитории для SSO используется файл `argocd-sso.yaml`.

Базовая идея такая:

1. `cert-manager` поднимает собственный self-signed `Root CA`.
2. От этого `Root CA` выпускаются TLS-сертификаты для `Gateway` и внутренних сервисов.
3. `trust-manager` публикует корневой сертификат в нужные namespace в виде `ConfigMap`.
4. `Dex` и `repoServer` в `Argo CD` монтируют этот trust bundle и начинают доверять `authentik` и другим внутренним endpoint'ам.

## Требования

- Kubernetes-кластер
- `kubectl`
- `Helm`
- DNS или `/etc/hosts`, которые резолвят:
  - `argocd.dev.local`
  - `auth.dev.local`
- Gateway `envoy-gateway` в namespace `envoy-gateway-system`, если используется `HTTPRoute`

> [!note]
> В этой схеме внешний TLS завершается на `Gateway`. Это значит, что сертификаты для `argocd.dev.local` и `auth.dev.local` выпускаются не в namespace приложений, а для listener'ов `Gateway` в namespace `envoy-gateway-system`. Сами `Argo CD` и `authentik` публикуются наружу через `HTTPRoute`.

> [!warning] Важно
> Self-signed PKI удобен для homelab, dev и внутренних сред. Для production нужно отдельно продумать ротацию, резервирование CA, распространение trust store и аварийное восстановление.

## Архитектура доверия

```text
SelfSigned ClusterIssuer
        |
        v
 Root CA Certificate + Secret
        |
        v
   CA ClusterIssuer
        |
        +--> Gateway certificate for *.dev.local / auth.dev.local / argocd.dev.local
        +--> Certificate for *.svc.cluster.local / internal services
        |
        v
 trust-manager Bundle
        |
        v
 ConfigMap trust-ca in namespaces argocd / auth / ...
```

## 1. Установка cert-manager

Официальная документация:

- https://cert-manager.io/docs/

Установка через Helm:

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.2 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

Проверка:

```bash
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager.io
```

## 2. Bootstrap собственного Root CA

### 2.1. Создать self-signed ClusterIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
```

Применение:

```bash
kubectl apply -f selfsigned-cluster-issuer.yaml
kubectl get clusterissuer selfsigned-cluster-issuer
```

### 2.2. Создать корневой CA сертификат

`Root CA` удобно хранить в namespace `cert-manager`, потому что потом этот же секрет сможет использовать `ClusterIssuer` типа `CA`.

> [!important] Почему здесь добавлен `subject`
> В официальной документации cert-manager есть важное замечание: для self-signed сертификатов лучше явно задавать `spec.subject`, чтобы избежать сертификата с пустым `Issuer DN`.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: homelab-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: homelab-root-ca
  secretName: homelab-root-ca-secret
  duration: 87600h # 10 years
  renewBefore: 720h # 30 days
  privateKey:
    algorithm: ECDSA
    size: 256
  subject:
    organizations:
      - Homelab
    organizationalUnits:
      - Platform
    countries:
      - RU
  issuerRef:
    name: selfsigned-cluster-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

Применение:

```bash
kubectl apply -f homelab-root-ca.yaml
kubectl get certificate -n cert-manager homelab-root-ca
kubectl get secret -n cert-manager homelab-root-ca-secret
```

### 2.3. Создать CA ClusterIssuer

После этого self-signed issuer нам нужен только для bootstrap. Все рабочие сертификаты удобнее выпускать уже через `CA` issuer.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: homelab-ca-issuer
spec:
  ca:
    secretName: homelab-root-ca-secret
```

Применение:

```bash
kubectl apply -f homelab-ca-cluster-issuer.yaml
kubectl get clusterissuer homelab-ca-issuer
```

## 3. Выпуск серверных сертификатов

Дальше можно выпускать сертификаты для любых сервисов, которым должен доверять `Argo CD`.

В этой статье есть два разных сценария:

1. Внешний TLS для доменов `auth.dev.local` и `argocd.dev.local` выпускается через `Gateway`.
2. Внутренние сертификаты для сервисов внутри кластера выпускаются обычными ресурсами `Certificate`.

### Вариант A. Внешний сертификат через Gateway

Если используется `Gateway API`, внешний сертификат удобнее выпускать прямо через `Gateway`. В репозитории уже используется такая схема: `HTTPRoute` у приложений ссылается на `envoy-gateway`, а TLS-секрет живёт у самого `Gateway`.

Пример:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-gateway
  namespace: envoy-gateway-system
  annotations:
    cert-manager.io/cluster-issuer: homelab-ca-issuer
spec:
  gatewayClassName: envoy-gateway-class
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "*.dev.local"
      tls:
        mode: Terminate
        certificateRefs:
          - name: envoy-tls-secret
      allowedRoutes:
        namespaces:
          from: All
```

В этой схеме:

- cert-manager выпускает сертификат для listener'а `Gateway`
- секрет `envoy-tls-secret` создаётся в namespace `envoy-gateway-system`
- `authentik` и `Argo CD` не обязаны иметь отдельные внешние TLS-секреты
- наружу они публикуются через `HTTPRoute`

Если listener использует wildcard hostname `*.dev.local`, одного сертификата на `Gateway` обычно достаточно сразу для:

- `auth.dev.local`
- `argocd.dev.local`

Если нужен не wildcard, а отдельный сертификат под конкретный hostname, можно описать отдельный listener или отдельный `Gateway` с нужным `hostname`.

### Вариант B. Сертификат для internal service DNS

Если нужен сертификат для внутреннего сервиса Kubernetes, тогда уже создаётся обычный ресурс `Certificate`.

Пример:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-internal-tls
  namespace: sandbox
spec:
  secretName: example-internal-tls
  dnsNames:
    - "*.sandbox.svc.cluster.local"
    - "*.sandbox"
  issuerRef:
    name: homelab-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

> [!note]
> Для SSO из этой статьи критично, чтобы сертификату `authentik` доверял `Dex`. Именно это и решается через `trust-manager`.

## 4. Установка trust-manager

Официальная документация:

- https://cert-manager.io/docs/trust/trust-manager/
- https://cert-manager.io/docs/trust/trust-manager/installation/

Вариант установки, который ты дал, подходит:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
```

```bash
helm upgrade trust-manager jetstack/trust-manager \
  --install \
  --namespace cert-manager \
  --wait
```

Для новых установок можно использовать и актуальный OCI chart из официальной документации:

```bash
helm upgrade trust-manager oci://quay.io/jetstack/charts/trust-manager \
  --install \
  --namespace cert-manager \
  --wait
```

Проверка:

```bash
kubectl get pods -n cert-manager
kubectl get deployments -n cert-manager trust-manager
```

## 5. Распространение Root CA через Bundle

### 5.1. Создать Bundle

> [!important]
> `Bundle` у `trust-manager` кластерный, а target `ConfigMap` создаётся в выбранных namespace с именем, совпадающим с именем `Bundle`.

Если `namespaceSelector` не задан, то `trust-manager` сейчас распространяет bundle во все namespace.

Ниже пример, который:

- добавляет системные CA (`useDefaultCAs: true`)
- добавляет наш собственный `Root CA` из секрета `homelab-root-ca-secret`
- публикует bundle в `ConfigMap trust-ca`

```yaml
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: trust-ca
spec:
  sources:
    - useDefaultCAs: true
    - secret:
        name: homelab-root-ca-secret
        key: tls.crt
  target:
    configMap:
      key: trust-bundle.pem
```

Применение:

```bash
kubectl apply -f trust-ca-bundle.yaml
kubectl get bundle trust-ca
kubectl get configmap trust-ca -n argocd -o yaml
kubectl get configmap trust-ca -n auth -o yaml
```

Внутри `ConfigMap` должен появиться ключ `trust-bundle.pem`.

> [!note]
> Такой вариант полезен, если ты хочешь явно контролировать, в какие namespace попадёт `trust-ca`.

## 6. Настройка authentik

### 6.1. Установка authentik

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update
```

Перед установкой сгенерируй `secret_key` для `authentik`:

```bash
openssl rand 60 | base64 -w 0
```

Получившееся значение нужно подставить в:

```yaml
authentik:
  secret_key: "<generated-secret-key>"
```

Пример values:

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

После установки открой:

```text
https://auth.dev.local/if/flow/initial-setup/
```

### 6.2. Создать OAuth2/OpenID Provider

В `authentik`:

- `Applications -> Providers`
- тип: `OAuth2/OpenID Provider`

Параметры:

- `Name`: `ArgoCD`
- `Client Type`: `Confidential`
- `Signing Key`: любой доступный ключ
- `Redirect URIs`:

```text
https://argocd.dev.local/api/dex/callback
http://localhost:8085/auth/callback
```

После создания сохранить:

- `Client ID`
- `Client Secret`

### 6.3. Создать Application

- `Name`: `ArgoCD`
- `Provider`: `ArgoCD`
- `Slug`: `argocd`
- `Launch URL`: `https://argocd.dev.local/auth/login`

### 6.4. Создать группы

- `ArgoCD Admins`
- `ArgoCD Viewers`

> [!warning]
> Имена групп в `authentik` должны совпадать с именами в `policy.csv`, иначе RBAC в `Argo CD` не сработает.

## 7. Настройка Argo CD

Основные идеи конфигурации:

- `Dex` подключается к `authentik` как к OIDC provider
- локальный `admin` отключен
- `clientSecret` должен храниться в секрете, а не в Git
- `Dex` и `repoServer` монтируют `ConfigMap trust-ca`

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

> [!warning]
> Не коммить реальные `clientSecret` в Git. Лучше передавать их через `ExternalSecret`, `SealedSecret` или другой механизм secret management.

## 8. Установка Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f argocd-sso.yaml
```

## 9. Проверка

Проверить ресурсы:

```bash
kubectl get pods -n cert-manager
kubectl get pods -n auth
kubectl get pods -n argocd
kubectl get clusterissuer
kubectl get certificate -A
kubectl get bundle trust-ca
kubectl get configmap trust-ca -n argocd
```

Проверить, что bundle смонтирован:

```bash
kubectl exec -n argocd deploy/argocd-dex-server -- ls /etc/ssl/certs
kubectl exec -n argocd deploy/argocd-repo-server -- ls /etc/ssl/certs
```

Открыть:

```text
https://argocd.dev.local
```

Проверка CLI:

```bash
argocd login argocd.dev.local --sso --grpc-web
```

## 10. Диагностика

Если SSO не работает, проверить:

- `Redirect URI` в `authentik` совпадает с `https://argocd.dev.local/api/dex/callback`
- `issuer` указывает на `https://auth.dev.local/application/o/argocd/`
- `clientID` и `clientSecret` перенесены без ошибок
- `ClusterIssuer homelab-ca-issuer` в статусе `Ready`
- сертификат на listener `Gateway` действительно выпущен от нужного CA
- `Bundle trust-ca` в статусе `Ready`
- в namespace `argocd` существует `ConfigMap trust-ca`
- в `ConfigMap trust-ca` есть ключ `trust-bundle.pem`
- `argocd-dex-server` и `argocd-repo-server` действительно смонтировали этот bundle
- пользователь в `authentik` входит в группу `ArgoCD Admins` или `ArgoCD Viewers`

Полезные команды:

```bash
kubectl logs -n cert-manager deploy/trust-manager
kubectl logs -n argocd deploy/argocd-dex-server
kubectl logs -n argocd deploy/argocd-server
kubectl get cm argocd-cm -n argocd -o yaml
kubectl get configmap trust-ca -n argocd -o yaml
kubectl describe bundle trust-ca
kubectl describe gateway -n envoy-gateway-system envoy-gateway
kubectl get secret -n envoy-gateway-system envoy-tls-secret -o yaml
```

## Краткий итог

Для этой схемы self-signed PKI рабочая последовательность такая:

1. Установить `cert-manager`.
2. Создать `selfsigned-cluster-issuer`.
3. Выпустить `Root CA` сертификат.
4. Создать `CA ClusterIssuer`.
5. Выпустить TLS-сертификат на `Gateway` и при необходимости отдельные внутренние сертификаты для сервисов.
6. Установить `trust-manager`.
7. Создать `Bundle trust-ca` и разложить trust bundle по namespace.
8. Смонтировать `trust-ca` в `Dex` и `repoServer`.
9. Настроить `authentik` и применить `argocd-sso.yaml`.

## Полезные ссылки

- cert-manager docs: https://cert-manager.io/docs/
- SelfSigned issuer: https://cert-manager.io/docs/configuration/selfsigned/
- CA issuer: https://cert-manager.io/docs/configuration/ca/
- trust-manager docs: https://cert-manager.io/docs/trust/trust-manager/
- trust-manager installation: https://cert-manager.io/docs/trust/trust-manager/installation/
