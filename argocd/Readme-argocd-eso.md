# Argo CD + External Secrets Operator + Vault

Этот сценарий описывает установку Argo CD через Helm chart с получением `argocd-secret` из Vault через External Secrets Operator.

В репозитории для этого используется values-файл [argocd-gateway-api-eso.yaml](https://github.com/vladoz77/k8s-applications/blob/main/argocd/argocd-gateway-api-eso.yaml).

Подробная заметка для Obsidian: [Obsidian-vault-eso-argocd.md](https://github.com/vladoz77/k8s-applications/blob/main/argocd/Obsidian-vault-eso-argocd.md)

## Что делает эта схема

- Argo CD ставится через chart `argo/argo-cd`
- chart не создает `argocd-secret` сам, потому что включено `configs.secret.createSecret: false`
- ESO читает секреты из Vault KV v2
- ESO создает Kubernetes Secret `argocd-secret` в namespace `argocd`
- Argo CD использует этот secret для `admin.password`, `admin.passwordMtime` и `server.secretkey`

## Требования

- установлен Vault
- в Vault включен и настроен `auth/kubernetes`
- установлен External Secrets Operator
- установлен `trust-manager`
- `trust-manager` публикует ConfigMap `trust-ca` с ключом `trust-bundle.pem` в namespace `argocd`
- есть доступ к `kubectl`, `helm`, `vault`, `htpasswd`, `openssl`

Важно:

- `SecretStore` в values-файле использует `caProvider.type: ConfigMap`, поэтому `trust-ca` должен существовать именно в namespace `argocd`
- в values-файле указан `path: infra` и `version: v2`
- поэтому в `remoteRef.key` указывается только `argocd`, а фактический путь в Vault будет `infra/argocd`
- если вы переходите с обычной установки Argo CD, проверьте, не остался ли старый `argocd-secret`, созданный самим chart

## 1. Подготовить namespace и trust-manager bundle

Если namespace еще не создан:

```bash
kubectl create namespace argocd
```

В этом сценарии предполагается, что `trust-ca` не создается вручную, а публикуется через `trust-manager`.

Нужно убедиться, что в namespace `argocd` появился ConfigMap:

```bash
kubectl get configmap trust-ca -n argocd
kubectl get configmap trust-ca -n argocd -o yaml
```

В ConfigMap должен быть ключ `trust-bundle.pem`, который содержит CA сертификат Vault.

## 2. Создать секрет в Vault KV v2

Секрет хранится по пути `infra/argocd`.

```bash
vault kv put infra/argocd \
  password=$(htpasswd -nbBC 10 "" 'password' | tr -d ':\n' | sed 's/$2y/$2a/') \
  secretkey="$(openssl rand -base64 32)" \
  passwordMtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Где:

- `password` это bcrypt-хеш пароля пользователя `admin`
- `secretkey` это ключ, который использует Argo CD для подписи сессий
- `passwordMtime` нужен Argo CD для корректного обновления пароля

Проверка:

```bash
vault kv get infra/argocd
```

Если в примере выше использована строка `'password'`, то логин в Argo CD будет:

- user: `admin`
- password: `password`

## 3. Создать policy в Vault

Для KV v2 policy должна ссылаться на API-пути `data` и `metadata`.

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

Проверка:

```bash
vault policy read argocd-policy
```

## 4. Создать role для Kubernetes auth

Role должна совпадать с тем, что описано в values-файле:

- ServiceAccount: `argocd-secrets-sa`
- namespace: `argocd`
- role: `argocd-role`

```bash
vault write auth/kubernetes/role/argocd-role \
  bound_service_account_names=argocd-secrets-sa \
  bound_service_account_namespaces=argocd \
  policies=argocd-policy \
  ttl=1h
```

Проверка:

```bash
vault read auth/kubernetes/role/argocd-role
```

## 5. Что лежит в `argocd-gateway-api-eso.yaml`

Файл [argocd-gateway-api-eso.yaml](https://github.com/vladoz77/k8s-applications/blob/main/argocd/argocd-gateway-api-eso.yaml) делает несколько важных вещей:

- отключает создание встроенного `argocd-secret`
- создает `SecretStore` для Vault
- создает `ExternalSecret`, который собирает `argocd-secret`
- создает `ServiceAccount` `argocd-secrets-sa`
- включает публикацию Argo CD через Gateway API `HTTPRoute`

Ключевая часть:

```yaml
configs:
  secret:
    createSecret: false

extraObjects:
  - apiVersion: external-secrets.io/v1
    kind: SecretStore
  - apiVersion: external-secrets.io/v1
    kind: ExternalSecret
  - apiVersion: v1
    kind: ServiceAccount
```

Сопоставление полей из Vault в `argocd-secret`:

- `password` -> `admin.password`
- `passwordMtime` -> `admin.passwordMtime`
- `secretkey` -> `server.secretkey`

## 6. Установить Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  --create-namespace \
  -f argocd-gateway-api-eso.yaml
```

## 7. Проверить, что ESO создал `argocd-secret`

Проверить ресурсы ESO:

```bash
kubectl get secretstore,externalsecret -n argocd
kubectl describe secretstore argocd-vault-backend -n argocd
kubectl describe externalsecret argocd-secret -n argocd
```

Проверить итоговый secret:

```bash
kubectl get secret argocd-secret -n argocd
kubectl get secret argocd-secret -n argocd -o yaml
```

Если это миграция с обычного values-файла, убедитесь, что `argocd-secret` теперь поддерживается через ESO, а не остался от старой установки.

Проверить запуск Argo CD:

```bash
kubectl get pods -n argocd
```

## 8. Обновление пароля admin

Для смены пароля нужно обновить данные в Vault и обязательно поменять `passwordMtime`.

```bash
vault kv put infra/argocd \
  password=$(htpasswd -nbBC 10 "" 'NewStrongPassword' | tr -d ':\n' | sed 's/$2y/$2a/') \
  secretkey="$(vault kv get -field=secretkey infra/argocd)" \
  passwordMtime="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

После этого ESO синхронизирует `argocd-secret` по `refreshInterval: 1h`.

Если нужно подтянуть изменения быстрее:

```bash
kubectl annotate externalsecret argocd-secret -n argocd force-sync=$(date +%s) --overwrite
```

## Диагностика

Если `argocd-secret` не появился, проверьте:

- установлен ли ESO и работают ли его pod'ы
- установлен ли `trust-manager`
- опубликован ли `trust-ca` в namespace `argocd`
- есть ли в `trust-ca` ключ `trust-bundle.pem`
- доступен ли Vault по адресу `https://vault.vault.svc.cluster.local:8200`
- включен ли auth method `kubernetes` в Vault
- совпадает ли имя role `argocd-role`
- совпадают ли `ServiceAccount` и namespace с ролью в Vault
- что policy использует именно KV v2 пути `infra/data/argocd` и `infra/metadata/argocd`

Полезные команды:

```bash
kubectl get pods -n external-secrets
kubectl logs -n external-secrets deploy/external-secrets
kubectl describe externalsecret argocd-secret -n argocd
kubectl describe secretstore argocd-vault-backend -n argocd
kubectl get configmap trust-ca -n argocd -o yaml
```

## Файлы сценария

- [argocd-gateway-api-eso.yaml](https://github.com/vladoz77/k8s-applications/blob/main/argocd/argocd-gateway-api-eso.yaml)
- [Readme.md](https://github.com/vladoz77/k8s-applications/blob/main/argocd/Readme.md)
