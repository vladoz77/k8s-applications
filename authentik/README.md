# Vault + PostgreSQL + authentik

Инструкция по развёртыванию `authentik` в Kubernetes с хранением секретов в HashiCorp Vault, синхронизацией через External Secrets Operator и использованием внешнего PostgreSQL.

В этом репозитории `authentik` не поднимает встроенную базу данных. Секреты для PostgreSQL и `AUTHENTIK_SECRET_KEY` хранятся в Vault, затем подтягиваются в Kubernetes через `ExternalSecret`.

## Схема интеграции

```text
Vault (kv-v2: infra)
  -> ClusterSecretStore
  -> ExternalSecret
  -> Kubernetes Secret
  -> PostgreSQL / authentik
```

## Структура проекта

```text
.
├── README.md
├── argocd-integration.md
├── assets/
├── authentik/
│   ├── authentik-default-values.yaml
│   ├── authentik-eso.yaml
│   └── authentik.yaml
└── database/
    ├── authentik-db-job.yaml
    └── postgresql-eso.yaml
```

Основные файлы:

- [`database/postgresql-eso.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/database/postgresql-eso.yaml) - PostgreSQL `StatefulSet`, сервисы и `ExternalSecret` для root-учётных данных БД.
- [`database/authentik-db-job.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/database/authentik-db-job.yaml) - `ExternalSecret` и `Job` для создания пользователя и базы данных `authentik`.
- [`authentik/authentik-eso.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/authentik/authentik-eso.yaml) - `values` для Helm chart `authentik` с интеграцией через External Secrets.

## Что понадобится

- Kubernetes-кластер
- `kubectl`
- `helm` 3.x
- HashiCorp Vault
- External Secrets Operator
- настроенный `Gateway API` и `Gateway` с именем `envoy-gateway` в namespace `envoy-gateway-system`
- DNS-запись или запись в `/etc/hosts` для `auth.dev.local`

## 1. Подготовить Vault

Включим `kv-v2` по пути `infra`:

```bash
vault secrets enable -path=infra kv-v2
```

Включим Kubernetes auth:

```bash
vault auth enable kubernetes
```

Создадим подключение Vault к кластеру:

```bash
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

Добавим root-секрет для PostgreSQL:

```bash
vault kv put infra/postgres \
  username=postgres \
  password=password
```

Добавим секрет для базы данных `authentik`:

```bash
vault kv put infra/authentik/database \
  username=authentik \
  password=password \
  database=authentik
```

Добавим секрет для `AUTHENTIK_SECRET_KEY`:

```bash
vault kv put infra/authentik/secret_key \
  authentik_secret_key="$(openssl rand -base64 60 | tr -d '\n')"
```

Создадим policy для чтения инфраструктурных секретов:

```bash
vault policy write infra-policy - <<'EOF'
path "infra/data/*" {
  capabilities = ["read"]
}

path "infra/metadata/*" {
  capabilities = ["list", "read"]
}
EOF
```

Создадим роль `infra-role` для `external-secrets`:

```bash
vault write auth/kubernetes/role/infra-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=infra-policy \
  ttl=1h
```

## 2. Создать ClusterSecretStore

`External Secrets Operator` будет забирать секреты из Vault через роль `infra-role`.

```bash
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: infra-vault-backend
spec:
  provider:
    vault:
      server: "https://vault.vault.svc.cluster.local:8200"
      path: infra
      version: v2
      caProvider:
        type: ConfigMap
        name: trust-ca
        namespace: external-secrets
        key: trust-bundle.pem
      auth:
        kubernetes:
          mountPath: kubernetes
          role: infra-role
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF
```

Проверьте, что `ClusterSecretStore` перешёл в `Ready`:

```bash
kubectl get clustersecretstore infra-vault-backend
```

## 3. Установить PostgreSQL

Файл [`database/postgresql-eso.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/database/postgresql-eso.yaml) создаёт:

- namespace `db`
- сервисы `postgresql-svc-headless` и `postgresql-svc`
- `StatefulSet` с PostgreSQL
- `ExternalSecret`, который подтягивает `username` и `password` из `infra/postgres`

Примените манифест:

```bash
kubectl apply -f database/postgresql-eso.yaml
```

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

## 4. Создать пользователя и базу для authentik

Файл [`database/authentik-db-job.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/database/authentik-db-job.yaml):

- забирает `username`, `password` и `database` из `infra/authentik/database`
- создаёт `Secret` `authentik-db-secret`
- запускает `Job`, который создаёт роль и базу в PostgreSQL, если они ещё не существуют

Примените манифест:

```bash
kubectl apply -f database/authentik-db-job.yaml
```

Проверка:

```bash
kubectl get externalsecret -n db
kubectl get jobs -n db
kubectl logs -n db job/pg-authentik-init
```

## 5. Установить authentik через Helm

Добавьте Helm-репозиторий:

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update
```

Файл [`authentik/authentik-eso.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/authentik/authentik-eso.yaml) уже содержит нужные настройки:

- namespace `auth`
- отключение встроенного PostgreSQL через `postgresql.enabled: false`
- подключение к внешнему PostgreSQL
- `ExternalSecret` с ключами:
  - `AUTHENTIK_POSTGRESQL__USER`
  - `AUTHENTIK_POSTGRESQL__PASSWORD`
  - `AUTHENTIK_POSTGRESQL__NAME`
  - `AUTHENTIK_SECRET_KEY`
- публикацию через `Gateway API` на хосте `auth.dev.local`

Установите chart:

```bash
helm upgrade --install authentik authentik/authentik \
  -f authentik/authentik-eso.yaml \
  -n auth \
  --create-namespace
```

Проверка:

```bash
kubectl get pods -n auth
kubectl get externalsecret -n auth
kubectl get secret -n auth authentik-secrets
kubectl get httproute -n auth
helm status authentik -n auth
```

## 6. Первый вход

После успешной установки откройте:

```text
https://auth.dev.local/if/flow/initial-setup/
```

## Как это работает

1. Vault хранит секреты по путям `infra/postgres`, `infra/authentik/database` и `infra/authentik/secret_key`.
2. `ClusterSecretStore` подключает External Secrets Operator к Vault.
3. `ExternalSecret` в namespace `db` создаёт `pg-secret` для PostgreSQL.
4. `ExternalSecret` и `Job` в namespace `db` создают отдельную базу и пользователя для `authentik`.
5. `ExternalSecret` в namespace `auth` создаёт `authentik-secrets`.
6. Helm chart `authentik` читает секреты через `envFrom` и подключается к внешней БД.

## Полезные команды

Переустановить `authentik` после изменения `values`:

```bash
helm upgrade --install authentik authentik/authentik \
  -f authentik/authentik-eso.yaml \
  -n auth
```

Удалить `authentik`:

```bash
helm uninstall authentik -n auth
```

Удалить `Job`, чтобы запустить его повторно:

```bash
kubectl delete job -n db pg-authentik-init
kubectl apply -f database/authentik-db-job.yaml
```

## Важные замечания

- В [`authentik/authentik-eso.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/authentik/authentik-eso.yaml) сейчас указаны SMTP-учётные данные прямо в `values`. Для production лучше вынести их в Vault и также подтягивать через `ExternalSecret`.
- `authentik` публикуется через `Gateway API`, а не через классический `Ingress`.
- Встроенный PostgreSQL у chart-а отключён, вся работа идёт с внешней БД из namespace `db`.
- Перед установкой убедитесь, что `external-secrets` service account действительно называется `external-secrets` и находится в namespace `external-secrets`.

## Дополнительно

- [`authentik/authentik-default-values.yaml`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/authentik/authentik-default-values.yaml) - базовые значения chart-а для сравнения.
- [`argocd-integration.md`](https://github.com/vladoz77/k8s-applications/blob/main/authentik/argocd-integration.md) - пример интеграции `authentik` с Argo CD через OIDC.
