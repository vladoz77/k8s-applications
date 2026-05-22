# Vault + Vault Provisioning + PostgreSQL + Authentik

Единая инструкция по развёртыванию `Vault`, автопровижинингу секретов и ролей, PostgreSQL для `authentik` и самого `authentik` в Kubernetes.

В этом проекте:

- `Vault` поднимается в `HA`-режиме с `TLS`
- `External Secrets Operator` забирает секреты из Vault в Kubernetes
- `PostgreSQL` разворачивается отдельно в namespace `db`
- `authentik` использует внешнюю БД и секреты из Vault

## Схема

```text
Vault
  -> infra/*
  -> ClusterSecretStore
  -> ExternalSecret
  -> Kubernetes Secret
  -> PostgreSQL / authentik
```

## Структура проекта

```text
.
├── README.md
├── cluster-keys.json
├── authentik/
│   ├── authentik-default-values.yaml
│   └── authentik-eso.yaml
├── database/
│   ├── authentik-db-job.yaml
│   └── postgresql-eso.yaml
└── vault/
    ├── certificate.yaml
    ├── ClusterSecretStore.yaml
    ├── Readme-eso.md
    ├── vault-default.yaml
    ├── vault-ha-tls-eso.yaml
    ├── vault-infra-provisioning-job.yaml
    └── vault-infra-provisioning.md
```

Основные файлы:

- `vault/certificate.yaml` - TLS certificate для Vault
- `vault/vault-ha-tls-eso.yaml` - Helm values для установки Vault
- `vault/vault-infra-provisioning-job.yaml` - Job для автопровижининга `infra`, `policy`, `role` и секретов
- `vault/ClusterSecretStore.yaml` - ClusterSecretStore для External Secrets Operator
- `database/postgresql-eso.yaml` - PostgreSQL и `ExternalSecret` для root-учётных данных
- `database/authentik-db-job.yaml` - Job для создания БД и пользователя `authentik`
- `authentik/authentik-eso.yaml` - Helm values для установки `authentik`

## Что нужно заранее

- Kubernetes-кластер
- `kubectl`
- `helm`
- `jq`
- `cert-manager`
- `ClusterIssuer` с именем `ca-issuer`
- ConfigMap `trust-ca` в namespace `external-secrets` с ключом `trust-bundle.pem`
- `Gateway API` и `Gateway` с именем `envoy-gateway` в namespace `envoy-gateway-system`
- DNS-запись или запись в `/etc/hosts` для `auth.dev.local`

## 1. Установить Vault

Добавьте Helm repo:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Создайте namespace и сертификат:

```bash
kubectl create namespace vault
kubectl apply -f vault/certificate.yaml
```

Установите Vault:

```bash
helm install vault hashicorp/vault -f vault/vault-ha-tls-eso.yaml -n vault
```

Проверка:

```bash
kubectl get pods -n vault
```

## 2. Установить External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
```

```bash
helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

Проверка:

```bash
kubectl get pods -n external-secrets
kubectl get sa -n external-secrets
```

## 3. Инициализировать и выполнить unseal Vault

Инициализируйте `vault-0` и сохраните ключи:

```bash
kubectl exec -n vault vault-0 -- \
  vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
```

Достаньте unseal key и root token:

```bash
export VAULT_UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' cluster-keys.json)
export VAULT_ROOT_TOKEN=$(jq -r '.root_token' cluster-keys.json)
```

Распечатайте все pod'ы Vault:

```bash
kubectl exec -n vault vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl exec -n vault vault-1 -- vault operator unseal "$VAULT_UNSEAL_KEY"
kubectl exec -n vault vault-2 -- vault operator unseal "$VAULT_UNSEAL_KEY"
```

Проверка:

```bash
kubectl exec -n vault vault-0 -- vault status
```

`cluster-keys.json` содержит чувствительные данные. Не коммитьте его и храните отдельно.

## 4. Автопровижининг Vault

После `init` и `unseal` создайте secret с root token:

```bash
kubectl create secret generic vault-root \
  -n vault \
  --from-literal=token="$VAULT_ROOT_TOKEN"
```

Запустите provisioning job:

```bash
kubectl apply -f vault/vault-infra-provisioning-job.yaml
```

Проверка:

```bash
kubectl logs -n vault job/vault-infra-provisioning -f
```

Этот `Job` автоматически:

- включает `kv-v2` на пути `infra`
- включает `auth/kubernetes`
- настраивает `auth/kubernetes/config`
- создаёт policy `infra-policy`
- создаёт role `infra-role` для `external-secrets`
- создаёт секреты:
  - `infra/postgres`
  - `infra/authentik/database`
  - `infra/authentik/secret_key`
  - `infra/authentik/bootstrap_password`
  - `infra/authentik/bootstrap_token`

Повторный запуск:

```bash
kubectl delete job -n vault vault-infra-provisioning
kubectl apply -f vault/vault-infra-provisioning-job.yaml
```
## 5. Создать ClusterSecretStore

Примените ClusterSecretStore:

```bash
kubectl apply -f vault/ClusterSecretStore.yaml
```

Проверка:

```bash
kubectl get clustersecretstores.external-secrets.io infra-vault-backend
kubectl describe clustersecretstores.external-secrets.io infra-vault-backend
```

Если store не переходит в `Ready`, сначала проверьте:

- существует ли ConfigMap `trust-ca` в namespace `external-secrets`
- существует ли service account `external-secrets` в namespace `external-secrets`
- доступен ли Vault по адресу `https://vault.vault.svc.cluster.local:8200`

## 6. Установить PostgreSQL

Примените манифест базы:

```bash
kubectl apply -f database/postgresql-eso.yaml
```

Что создаётся:

- namespace `db`
- `StatefulSet` PostgreSQL
- сервисы `postgresql-svc` и `postgresql-svc-headless`
- `ExternalSecret` `pg-external-secret`
- secret `pg-secret` из Vault path `infra/postgres`

Проверка:

```bash
kubectl get pods -n db
kubectl get externalsecret -n db
kubectl get secret -n db pg-secret
```

PostgreSQL будет доступен внутри кластера по адресу:

```text
postgresql-svc.db.svc.cluster.local:5432
```

## 7. Создать пользователя и базу для authentik

Примените job:

```bash
kubectl apply -f database/authentik-db-job.yaml
```

Что делает этот манифест:

- забирает из Vault секрет `infra/authentik/database`
- создаёт Kubernetes secret `authentik-db-secret`
- запускает `Job` `pg-authentik-init`
- создаёт роль и БД `authentik`, если они ещё не существуют

Проверка:

```bash
kubectl get externalsecret -n db
kubectl get jobs -n db
kubectl logs -n db job/pg-authentik-init
```

Если нужно прогнать job повторно:

```bash
kubectl delete job -n db pg-authentik-init
kubectl apply -f database/authentik-db-job.yaml
```

## 8. Установить authentik

Добавьте Helm repo:

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update
```

Установите chart:

```bash
helm upgrade --install authentik authentik/authentik \
  -f authentik/authentik-eso.yaml \
  -n auth \
  --create-namespace
```

Что уже настроено в `authentik/authentik-eso.yaml`:

- namespace `auth`
- отключён встроенный PostgreSQL
- включено подключение к `postgresql-svc.db.svc.cluster.local`
- создаётся `ExternalSecret` `authentik-secrets`
- в `authentik-secrets` попадают:
  - `AUTHENTIK_POSTGRESQL__USER`
  - `AUTHENTIK_POSTGRESQL__PASSWORD`
  - `AUTHENTIK_POSTGRESQL__NAME`
  - `AUTHENTIK_SECRET_KEY`
  - `AUTHENTIK_BOOTSTRAP_PASSWORD`
  - `AUTHENTIK_BOOTSTRAP_TOKEN`
- публикация идёт через `Gateway API` на хост `auth.dev.local`

Проверка:

```bash
kubectl get pods -n auth
kubectl get externalsecret -n auth
kubectl get secret -n auth authentik-secrets
kubectl get httproute -n auth
helm status authentik -n auth
```

## 9. Первый вход

После успешной установки откройте:

```text
https://auth.dev.local/if/flow/initial-setup/
```

Bootstrap-данные лежат в Vault:

- `infra/authentik/bootstrap_password`
- `infra/authentik/bootstrap_token`

Также после синхронизации они попадут в secret `authentik-secrets` в namespace `auth`.

## Полезные команды

Проверить Vault:

```bash
kubectl get pods -n vault
kubectl exec -n vault vault-0 -- vault status
kubectl logs -n vault job/vault-infra-provisioning
```

Проверить ESO:

```bash
kubectl get pods -n external-secrets
kubectl get clustersecretstores.external-secrets.io
```

Проверить PostgreSQL:

```bash
kubectl get pods -n db
kubectl get secret -n db pg-secret
kubectl logs -n db job/pg-authentik-init
```

Проверить authentik:

```bash
kubectl get pods -n auth
kubectl get httproute -n auth
helm status authentik -n auth
```

Переустановить authentik после изменения values:

```bash
helm upgrade --install authentik authentik/authentik \
  -f authentik/authentik-eso.yaml \
  -n auth \
  --create-namespace
```

Удалить authentik:

```bash
helm uninstall authentik -n auth
```

Удалить Vault:

```bash
helm uninstall vault -n vault
```

## Порядок установки в одном списке

1. `kubectl apply -f vault/certificate.yaml`
2. `helm install vault hashicorp/vault -f vault/vault-ha-tls-eso.yaml -n vault`
3. `helm install external-secrets external-secrets/external-secrets --namespace external-secrets --create-namespace --set installCRDs=true`
4. `vault operator init`
5. `vault operator unseal` для всех pod'ов
6. `kubectl create secret generic vault-root -n vault --from-literal=token="$VAULT_ROOT_TOKEN"`
7. `kubectl apply -f vault/vault-infra-provisioning-job.yaml`
8. `kubectl apply -f vault/ClusterSecretStore.yaml`
9. `kubectl apply -f database/postgresql-eso.yaml`
10. `kubectl apply -f database/authentik-db-job.yaml`
11. `helm upgrade --install authentik authentik/authentik -f authentik/authentik-eso.yaml -n auth --create-namespace`

## Важные замечания

- В `authentik/authentik-eso.yaml` сейчас SMTP-учётные данные находятся прямо в values. Для production лучше вынести их в Vault и также подтягивать через `ExternalSecret`.
- `vault-root` нужен только для bootstrap. После первого успешного provisioning его лучше удалить или заменить на менее привилегированный токен.
- `vault-infra-provisioning-job.yaml` идемпотентен и не перезаписывает уже существующие секреты в `infra/*`.
- Если `ExternalSecret` не синхронизируется, почти всегда проблема либо в `ClusterSecretStore`, либо в `trust-ca`, либо в доступности Vault service.
