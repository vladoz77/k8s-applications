# Коллекция Kubernetes приложений и сервисов

Этот репозиторий содержит набор конфигураций и манифестов для развертывания различных приложений и сервисов в Kubernetes кластере.

## Структура репозитория

- **argocd/** - Конфигурация ArgoCD для непрерывной доставки в Kubernetes
- **authentik/** - Система управления идентификацией и доступом
- **cert-manager/** - Автоматическое управление SSL/TLS сертификатами
- **es/** - Конфигурация Elasticsearch
- **Goldilocks/** - Инструмент для оптимизации ресурсов с VPA
- **harbor/** - Реестр контейнеров Harbor
- **ingress/** - Настройка Ingress NGINX контроллера
- **istio/** - Service mesh решение
- **kyeverno/** - Политики управления кластером
- **localpathprovsioner/** - Локальное хранилище для разработки
- **logging/** - Стек для логирования (Elasticsearch, Fluent-bit, Kibana)
- **loki/** - Система сбора и анализа логов
- **longhorn/** - Распределенное хранилище данных
- **metallb/** - Балансировщик нагрузки для bare metal кластеров
- **metrics-server/** - Сбор метрик кластера
- **minio/** - Объектное хранилище совместимое с S3
- **nfs-subdir-provision/** - NFS провайдер для хранения данных
- **postgres/** - База данных PostgreSQL с pgAdmin
- **redis/** - In-memory база данных Redis
- **reloader/** - Автоматическая перезагрузка подов при изменении конфигмапов
- **tempo/** - Распределенная система трейсинга
- **vault/** - Управление секретами с Hashicorp Vault
- **victoria-metrics-monitoring/** - Мониторинг на базе Victoria Metrics

## Предварительные требования

- Kubernetes кластер (версия 1.20+)
- kubectl
- helm (версия 3+)
- ArgoCD (для GitOps подхода)

## Установка

Каждый компонент содержит свой собственный README с инструкциями по установке и настройке.

Базовая установка через ArgoCD:

```bash
# Установка ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f argocd/argocd.yaml

# Установка CLI
./argocd/install-argocd-cli.sh
```

## Основные компоненты

### Управление кластером
- ArgoCD - Непрерывная доставка
- Kyverno - Политики и управление
- Reloader - Автоматическое обновление

### Хранение данных
- Longhorn - Основное хранилище
- MinIO - Объектное хранилище
- PostgreSQL - Реляционная БД
- Redis - In-memory хранилище

### Безопасность
- Authentik - IAM решение
- Cert-manager - Управление сертификатами
- Vault - Управление секретами

### Мониторинг и логирование
- Victoria Metrics - Метрики
- Loki - Логи
- Tempo - Трейсинг
- Elasticsearch/Kibana - Анализ логов

### Сетевые компоненты
- Ingress NGINX
- MetalLB
- Istio

