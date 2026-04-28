---
tags:
  - argocd
  - vault
  - external-secrets
  - eso
  - kubernetes
  - obsidian
aliases:
  - Vault ESO ArgoCD
  - ArgoCD Secret From Vault
---

# Vault + ESO + Argo CD

## Кратко

Эта заметка описывает схему, в которой `argocd-secret` не создается самим Helm chart Argo CD, а синхронизируется из Vault через External Secrets Operator.

Рабочий values-файл в этом репозитории: [argocd-gateway-api-eso.yaml](https://github.com/vladoz77/k8s-applications/blob/main/argocd/argocd-gateway-api-eso.yaml)

Короткая версия инструкции: [Readme-argocd-eso.md](https://github.com/vladoz77/k8s-applications/blob/main/argocd/Readme-argocd-eso.md)

---

## Зачем это нужно

Обычно Argo CD может сам создать `argocd-secret` и хранить в нем:

- `admin.password`
- `admin.passwordMtime`
- `server.secretkey`

Но в production-сценарии часто хочется:

- не хранить даже хеши паролей в Git
- централизовать управление секретами через Vault
- иметь единый паттерн для всех приложений в кластере
- менять секреты без ручного редактирования Kubernetes Secret

В этой схеме Argo CD получает секреты опосредованно:

`Vault KV v2 -> SecretStore -> ExternalSecret -> Kubernetes Secret argocd-secret -> Argo CD`

---

## Когда это оправдано

> [!tip] Использовать стоит
> Если в кластере уже есть `Vault`, `External Secrets Operator` и `trust-manager`, а команда приняла практику "все секреты живут в Vault".

> [!warning] Может быть избыточно
> Если весь смысл сводится только к тому, чтобы не хранить `admin.password`, а сам `admin` нужен только для первого входа и потом будет отключен в пользу SSO.

### Плюсы

- секреты не лежат в Git
- секреты централизованно ротируются через Vault
- единый подход для Argo CD и остальных приложений
- можно позже добавлять другие чувствительные данные в ту же схему

### Минусы

- больше зависимостей на старте
- сложнее диагностика
- больше компонентов в цепочке отказа

---

## Компоненты схемы

### 1. Vault

Vault хранит секрет по пути:

```text
infra/argocd
```

Внутри секрета используются поля:

- `password`
- `secretkey`
- `passwordMtime`

### 2. External Secrets Operator

ESO читает секреты из Vault и создает обычный Kubernetes Secret.

### 3. SecretStore

`SecretStore` описывает:

- адрес Vault
- KV engine path
- версию KV (`v2`)
- способ аутентификации в Vault
- источник CA для TLS

### 4. trust-manager

`trust-manager` публикует доверенную CA в ConfigMap `trust-ca`.

В вашем сценарии это важно, потому что `SecretStore` использует:

```yaml
caProvider:
  type: ConfigMap
  name: trust-ca
  key: trust-bundle.pem
```

То есть `ESO` доверяет Vault именно через bundle, опубликованный `trust-manager`.

### 5. Argo CD Helm chart

Chart Argo CD ставит сами компоненты Argo CD, но **не создает** встроенный `argocd-secret`, потому что это отключено:

```yaml
configs:
  secret:
    createSecret: false
```

---

## Целевая архитектура

```text
Vault (KV v2, path=infra/argocd)
  |
  | read via kubernetes auth
  v
External Secrets Operator
  |
  | SecretStore: argocd-vault-backend
  | ExternalSecret: argocd-secret
  v
Kubernetes Secret: argocd/argocd-secret
  |
  v
Argo CD server
```

---

## Что именно лежит в репозитории

- values-файл: [argocd-gateway-api-eso.yaml](https://github.com/vladoz77/k8s-applications/blob/main/argocd/argocd-gateway-api-eso.yaml)
- краткая инструкция: [Readme-argocd-eso.md](https://github.com/vladoz77/k8s-applications/blob/main/argocd/Readme-argocd-eso.md)
- общий README: [Readme.md](https://github.com/vladoz77/k8s-applications/blob/main/argocd/Readme.md)

---

## Как это работает по шагам

### Шаг 1. trust-manager публикует CA bundle

В namespace `argocd` должен существовать ConfigMap:

- name: `trust-ca`
- key: `trust-bundle.pem`

Проверка:

```bash
kubectl get configmap trust-ca -n argocd
kubectl get configmap trust-ca -n argocd -o yaml
```

Если этого ConfigMap нет, `SecretStore` не сможет установить TLS-соединение с Vault.

### Шаг 2. В Vault создается секрет `infra/argocd`

```bash
vault kv put infra/argocd \
  password=$(htpasswd -nbBC 10 "" 'password' | tr -d ':\n' | sed 's/$2y/$2a/') \
  secretkey="$(openssl rand -base64 32)" \
  passwordMtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Расшифровка:

- `password` это bcrypt-хеш пароля пользователя `admin`
- `secretkey` это ключ для подписи cookie и сессий Argo CD
- `passwordMtime` метка изменения пароля, которая нужна Argo CD

Проверка:

```bash
vault kv get infra/argocd
```

### Шаг 3. В Vault создается policy

Для KV v2 policy должна смотреть не на логический путь `infra/argocd`, а на API path:

```bash
vault policy write argocd-policy - <<EOF
path "infra/data/argocd" {
  capabilities = ["read"]
}
path "infra/metadata/argocd" {
  capabilities = ["list", "read"]
}
EOF
```

Почему так:

- `data` нужен для чтения значения секрета
- `metadata` нужен для операций, связанных с KV v2 и листингом версий/метаданных

Проверка:

```bash
vault policy read argocd-policy
```

### Шаг 4. В Vault создается kubernetes role

```bash
vault write auth/kubernetes/role/argocd-role \
  bound_service_account_names=argocd-secrets-sa \
  bound_service_account_namespaces=argocd \
  policies=argocd-policy \
  ttl=1h
```

Эта role означает:

- токен service account `argocd-secrets-sa`
- только в namespace `argocd`
- получает policy `argocd-policy`

Проверка:

```bash
vault read auth/kubernetes/role/argocd-role
```

### Шаг 5. Helm chart создает `ServiceAccount`, `SecretStore`, `ExternalSecret`

Это описано в [argocd-gateway-api-eso.yaml](https://github.com/vladoz77/k8s-applications/blob/main/argocd/argocd-gateway-api-eso.yaml) через `extraObjects`.

Создаются:

- `ServiceAccount` `argocd-secrets-sa`
- `SecretStore` `argocd-vault-backend`
- `ExternalSecret` `argocd-secret`

Ниже эквивалент полных manifest-объектов, которые описаны в values-файле.

### ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-secrets-sa
  namespace: argocd
```

### SecretStore

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: argocd-vault-backend
  namespace: argocd
spec:
  provider:
    vault:
      server: "https://vault.vault.svc.cluster.local:8200"
      path: infra
      version: v2
      caProvider:
        type: ConfigMap
        name: trust-ca
        key: trust-bundle.pem
      auth:
        kubernetes:
          mountPath: kubernetes
          role: argocd-role
          serviceAccountRef:
            name: argocd-secrets-sa
```

### ExternalSecret

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: argocd-vault-backend
    kind: SecretStore
  target:
    name: argocd-secret
    creationPolicy: Owner
    template:
      type: Opaque
  data:
    - secretKey: admin.password
      remoteRef:
        key: argocd
        property: password
    - secretKey: server.secretkey
      remoteRef:
        key: argocd
        property: secretkey
    - secretKey: admin.passwordMtime
      remoteRef:
        key: argocd
        property: passwordMtime
```

Что важно в этих manifest'ах:

- `ServiceAccount` используется ESO для входа в Vault через `auth/kubernetes`
- `SecretStore` задает адрес Vault, KV path `infra`, trust через `trust-ca` и роль `argocd-role`
- `ExternalSecret` собирает финальный Kubernetes Secret `argocd-secret` из полей Vault secret `infra/argocd`

### Шаг 6. ESO читает Vault и создает `argocd-secret`

`ExternalSecret` берет:

- `password` -> `admin.password`
- `passwordMtime` -> `admin.passwordMtime`
- `secretkey` -> `server.secretkey`

И создает Kubernetes Secret:

```text
argocd/argocd-secret
```

### Шаг 7. Argo CD использует этот secret

После появления `argocd-secret` Argo CD server может использовать:

- пароль `admin`
- timestamp изменения пароля
- server secret key

---

## Разбор values-файла

### Отключение встроенного секрета

```yaml
configs:
  secret:
    createSecret: false
```

Это ключевой момент.

Если этого не сделать, chart сам создаст `argocd-secret`, и вы получите конфликт между chart-managed и ESO-managed секретом.

### SecretStore

Смысл текущей конфигурации:

```yaml
spec:
  provider:
    vault:
      server: "https://vault.vault.svc.cluster.local:8200"
      path: infra
      version: v2
```

Это значит:

- секреты читаются из Vault
- движок расположен на `infra`
- используется KV v2

Из-за этого `remoteRef.key: argocd` резолвится как:

```text
infra/argocd
```

### TLS trust через trust-manager

```yaml
caProvider:
  type: ConfigMap
  name: trust-ca
  key: trust-bundle.pem
```

Это значит:

- ESO не использует системный trust store контейнера
- ESO берет CA из ConfigMap
- ConfigMap должен находиться в том же namespace, что и `SecretStore`

В вашем случае:

- namespace: `argocd`
- ConfigMap: `trust-ca`

### Kubernetes auth

```yaml
auth:
  kubernetes:
    mountPath: kubernetes
    role: argocd-role
    serviceAccountRef:
      name: argocd-secrets-sa
```

Это означает:

- ESO использует service account `argocd-secrets-sa`
- обращается в auth backend Vault по пути `auth/kubernetes`
- запрашивает role `argocd-role`

---

## Установка

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f argocd-gateway-api-eso.yaml
```

После установки проверьте:

```bash
kubectl get pods -n argocd
kubectl get secretstore,externalsecret -n argocd
kubectl get secret argocd-secret -n argocd
```

---

## Проверки после установки

### Проверить SecretStore

```bash
kubectl describe secretstore argocd-vault-backend -n argocd
```

Ищем:

- статус `Ready`
- отсутствие TLS/auth ошибок

### Проверить ExternalSecret

```bash
kubectl describe externalsecret argocd-secret -n argocd
```

Ищем:

- успешную синхронизацию
- отсутствие ошибок чтения из Vault

### Проверить итоговый Kubernetes Secret

```bash
kubectl get secret argocd-secret -n argocd -o yaml
```

Ожидаемые ключи:

- `admin.password`
- `admin.passwordMtime`
- `server.secretkey`

---

## Миграция с обычной установки Argo CD

Если Argo CD уже стоял раньше, возможна ситуация, когда `argocd-secret` уже существует и был создан chart'ом.

Что важно проверить:

- `configs.secret.createSecret` действительно выключен
- существующий `argocd-secret` не остался от прошлой установки
- ESO действительно владеет этим secret

Признаки нормального состояния:

- `ExternalSecret` синхронизирован
- `argocd-secret` обновляется при изменении данных в Vault

---

## Ротация пароля admin

Для смены пароля нужно обновить Vault secret и обязательно изменить `passwordMtime`.

```bash
vault kv put infra/argocd \
  password=$(htpasswd -nbBC 10 "" 'NewStrongPassword' | tr -d ':\n' | sed 's/$2y/$2a/') \
  secretkey="$(vault kv get -field=secretkey infra/argocd)" \
  passwordMtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

После этого ESO подтянет новые значения согласно:

```yaml
refreshInterval: 1h
```

Если нужно принудительно инициировать быструю синхронизацию:

```bash
kubectl annotate externalsecret argocd-secret -n argocd force-sync=$(date +%s) --overwrite
```

---

## Что еще имеет смысл хранить через ESO для Argo CD

Помимо `admin.password` и `server.secretkey`, через ESO часто имеет смысл вести:

- OIDC client secret
- webhook secrets
- repo credentials
- токены интеграций
- credentials для notification providers

Хорошее правило:

- все чувствительные runtime secrets держать в Vault
- все обычные chart settings оставлять в Git

---

## Что не стоит смешивать в одном секрете без необходимости

Лучше не складывать в `argocd-secret` подряд все, что относится к Argo CD.

Причины:

- сложнее ротация
- сложнее аудит изменений
- выше шанс случайно сломать базовый логин/сессии

Практичнее разделять:

- базовые bootstrap secrets Argo CD
- SSO secrets
- repo credentials
- integration secrets

---

## Типовые проблемы

### 1. `SecretStore` не готов

Проверьте:

- существует ли `trust-ca`
- есть ли в нем `trust-bundle.pem`
- доступен ли `vault.vault.svc.cluster.local:8200`
- совпадает ли CA Vault с тем, что публикует `trust-manager`

Команды:

```bash
kubectl get configmap trust-ca -n argocd -o yaml
kubectl describe secretstore argocd-vault-backend -n argocd
```

### 2. Ошибка авторизации в Vault

Проверьте:

- включен ли `auth/kubernetes`
- совпадает ли role `argocd-role`
- совпадает ли namespace `argocd`
- совпадает ли service account `argocd-secrets-sa`

Команды:

```bash
kubectl describe sa argocd-secrets-sa -n argocd
vault read auth/kubernetes/role/argocd-role
```

### 3. Ошибка из-за KV v2 path

Частая ошибка: путать logical path и API path.

Нужно помнить:

- секрет пишется в `infra/argocd`
- policy читает `infra/data/argocd`
- metadata читается из `infra/metadata/argocd`

### 4. Argo CD не подхватил новый пароль

Проверьте:

- был ли обновлен `passwordMtime`
- синхронизировал ли ESO новый secret
- обновился ли сам Kubernetes Secret

---

## Диагностика

Базовый набор команд:

```bash
kubectl get pods -n external-secrets
kubectl logs -n external-secrets deploy/external-secrets
kubectl get secretstore,externalsecret -n argocd
kubectl describe secretstore argocd-vault-backend -n argocd
kubectl describe externalsecret argocd-secret -n argocd
kubectl get secret argocd-secret -n argocd -o yaml
kubectl get configmap trust-ca -n argocd -o yaml
vault kv get infra/argocd
vault policy read argocd-policy
vault read auth/kubernetes/role/argocd-role
```

---

## Практическая рекомендация

Если это production или платформа с единым secret-management, схема `Vault + ESO + Argo CD` выглядит оправданно.

Если это dev/lab и нужен только начальный `admin`-пароль, можно оставить более простой вариант без ESO и не усложнять bootstrap.

Оптимальный компромисс:

- bootstrap secret для Argo CD можно вести через ESO
- после включения SSO локального `admin` лучше ограничить или отключить
- дополнительные интеграционные секреты также держать в Vault

---

## Checklist

### Перед установкой

- [ ] namespace `argocd` существует
- [ ] `trust-manager` установлен
- [ ] ConfigMap `trust-ca` существует в namespace `argocd`
- [ ] Vault доступен по TLS
- [ ] ESO установлен
- [ ] в Vault есть secret `infra/argocd`
- [ ] в Vault есть policy `argocd-policy`
- [ ] в Vault есть role `argocd-role`

### После установки

- [ ] создан `ServiceAccount` `argocd-secrets-sa`
- [ ] `SecretStore` `argocd-vault-backend` в статусе `Ready`
- [ ] `ExternalSecret` `argocd-secret` синхронизирован
- [ ] Kubernetes Secret `argocd-secret` существует
- [ ] Argo CD pods в namespace `argocd` запущены
