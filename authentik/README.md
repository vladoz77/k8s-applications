# Authentik

Инструкция по установке `authentik` в Kubernetes через Helm chart с конфигурацией из этого каталога.

## Что используется в этом репозитории

- Установка в namespace `auth`
- Развёртывание через chart `authentik/authentik`
- Встроенный PostgreSQL (`postgresql.enabled: true`)
- Публикация наружу через `Gateway API` (`HTTPRoute`), а не через классический `Ingress`
- Хост по умолчанию: `auth.dev.local`

## Предварительные требования

- Kubernetes-кластер с рабочим `kubectl`
- `helm` 3.x
- Настроенный `Gateway API` и `Gateway` с именем `envoy-gateway` в namespace `envoy-gateway-system`
- DNS-запись или запись в `/etc/hosts` для `auth.dev.local`

Если `Gateway API` или `envoy-gateway` не настроены, текущий `values.yaml` не сможет опубликовать сервис наружу.

## Подготовка

1. Добавьте Helm-репозиторий:

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update
```

2. Сгенерируйте `secret_key`:

```bash
openssl rand 60 | base64 -w 0
```

3. Откройте [values.yaml](https://github.com/vladoz77/k8s-applications/blob/main/authentik/values.yaml) и перед установкой замените:

- `authentik.secret_key`
- `authentik.email.username`
- `authentik.email.password`
- `authentik.email.from`
- `authentik.postgresql.password`
- `postgresql.auth.password`
- `server.route.main.hostnames`, если нужен другой FQDN
- `server.route.main.parentRefs`, если в кластере используется другой `Gateway`

Текущий `values.yaml` выглядит как пример для локального стенда. Для production лучше выносить секреты в `Secret` или внешний secret manager, а не хранить их в git.

## Установка

Запустите установку chart-а:

```bash
helm upgrade --install authentik authentik/authentik \
  -f values.yaml \
  -n auth \
  --create-namespace
```

## Проверка

Проверьте, что поды поднялись:

```bash
kubectl get pods -n auth
```

Проверьте сервисы и маршрут:

```bash
kubectl get svc -n auth
kubectl get httproute -n auth
```

При необходимости посмотрите статус релиза:

```bash
helm status authentik -n auth
```

## Первый вход

После успешной установки откройте:

```text
https://auth.dev.local/if/flow/initial-setup/
```

Через этот URL выполняется первоначальная настройка администратора `authentik`.

## Полезные команды

Обновить релиз после изменения `values.yaml`:

```bash
helm upgrade --install authentik authentik/authentik \
  -f values.yaml \
  -n auth
```

Удалить установку:

```bash
helm uninstall authentik -n auth
```

## Дополнительно

- Базовая конфигурация chart-а: [authentik-default-values.yaml](https://github.com/vladoz77/k8s-applications/blob/main/authentik/authentik-default-values.yaml)
- Интеграция с Argo CD через OIDC: [argocd-integration.md](https://github.com/vladoz77/k8s-applications/blob/main/authentik/argocd-integration.md)
