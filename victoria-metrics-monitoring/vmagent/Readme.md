# vmagent - Victoria Metrics Agent

**vmagent** - это легковесный агент для сбора метрик из различных источников и отправки их в Victoria Metrics. Это основной компонент для телеметрии во всей системе мониторинга.

## Описание

vmagent собирает метрики из Kubernetes кластера и других источников, преобразует их согласно правилам релабелирования и отправляет в Victoria Metrics для хранения и анализа. Агент использует Kubernetes Service Discovery для автоматического обнаружения мониторящихся сервисов.

### Ключевые возможности

- **Kubernetes Service Discovery**: Автоматическое обнаружение подов, сервисов, узлов для мониторинга
- **Множество форматов**: Поддержка Prometheus, InfluxDB, Graphite, OpenTSDB форматов
- **Релабелирование**: Мощная система переименования меток для гибкой обработки метрик
- **TLS поддержка**: Защищенное подключение к защищенным компонентам (etcd, API сервер)
- **Горизонтальное масштабирование**: StatefulSet с поддержкой кластерного режима
- **Горячая перезагрузка**: ConfigMap Reloader автоматически перезапускает агент при изменении конфигурации
- **Низкие ресурсы**: Минимальные требования к CPU и памяти

## Архитектура развертывания

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    vmagent Pod                            │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────┐     │   │
│  │ │ etcd    │  │ kubelet │  │ calico  │  │ node-exp │     │   │
│  │ └────┬────┘  └────┬────┘  └────┬────┘  └────┬─────┘     │   │
│  │      │            │            │             │           │   │
│  │      └────────────┼────────────┼─────────────┘           │   │
│  │                   ▼                                       │   │
│  │            Scrape Targets                                │   │
│  │            ↓ Process & Relabel                           │   │
│  │            Metrics Stream                                │   │
│  └────────────────────┬───────────────────────────────────┘   │
│                       │                                         │
└───────────────────────┼─────────────────────────────────────────┘
                        │ HTTP
        ┌───────────────▼──────────────┐
        │  vmsingle/vmcluster:8428    │
        │  (Victoria Metrics Storage)   │
        └───────────────────────────────┘
```

## Структура файлов конфигурации

```
vmagent/
├── vmagent.yaml              # Helm values конфигурация (основной файл)
├── vmagent-default.yaml      # Значения по умолчанию (для справки)
├── scrape-config.yaml        # ConfigMap с правилами сбора метрик
├── etcd-secret-writer.yaml   # Job для создания TLS секретов etcd
├── Readme.md                 # Этот файл
└── notes/                    # Дополнительная документация (если есть)
```

### vmagent.yaml - Helm Values

Основной файл конфигурации для развертывания vmagent через Helm. Содержит:

- **Режим развертывания**: StatefulSet для сохранения состояния
- **Репликация**: replicaCount и replicationFactor
- **Ресурсы**: CPU/memory запросы и лимиты
- **Хранилище**: Persistent volume для WAL (Write-Ahead Log)
- **Сетевая конфигурация**: Service и Ingress
- **TLS/Сертификаты**: Монтирование секретов
- **Конфигурация скрейпа**: Ссылка на ConfigMap с правилами сбора

### scrape-config.yaml - ConfigMap

Содержит все правила сбора метрик разбитые на логические секции:

| Секция | Назначение | Источник |
|--------|-----------|----------|
| `kubernetes-scrape-config.yaml` | Метрики ядра Kubernetes (etcd, API server, kubelet, scheduler, controller-manager, kube-proxy) | Kubernetes компоненты |
| `calico-scrape-config.yaml` | Метрики CNI (сетевой плагин) | Calico felix, typha, controllers |
| `kube-state-metrics-scrape-config.yaml` | Состояние K8s ресурсов (Pods, Services, Deployments, etc) | kube-state-metrics сервис |
| `node-exporter-scrape-config.yaml` | Метрики хоста (CPU, память, диск, сеть) | node-exporter DaemonSet |
| `minio-scrape-config.yaml` | Метрики S3 хранилища | MinIO объектное хранилище |
| `autodiscovery-scrape-config.yaml` | Автоматическое обнаружение по аннотациям | Любые сервисы/поды с аннотациями |

## Развертывание

### Предварительные требования

1. **Helm 3.x** установлен
2. **Helm репозиторий Victoria Metrics** добавлен:
   ```bash
   helm repo add vm https://victoriametrics.github.io/helm-charts/
   helm repo update
   ```
3. **Storage Class** доступен (например, `local-path`)
4. **TLS Секреты** созданы (для защищенных компонентов):
   ```bash
   kubectl create secret generic etcd-secrets \
     --from-file=/etc/kubernetes/pki/etcd/server.crt \
     --from-file=/etc/kubernetes/pki/etcd/server.key \
     --from-file=/etc/kubernetes/pki/etcd/ca.crt \
     -n monitoring
   ```

### Шаг за шагом

1. **Создайте namespace** (если еще не создан):
   ```bash
   kubectl create namespace monitoring
   ```

2. **Создайте ConfigMap со скрейп конфигом**:
   ```bash
   kubectl apply -f vmagent/scrape-config.yaml
   ```

3. **Установите vmagent через Helm**:
   ```bash
   helm upgrade --install vmagent vm/victoria-metrics-agent \
     -f vmagent/vmagent.yaml \
     -n monitoring \
     --create-namespace
   ```

4. **Проверьте статус**:
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=vmagent
   kubectl logs -n monitoring -l app.kubernetes.io/name=vmagent -f
   ```

## Конфигурация

### Основные параметры в vmagent.yaml

#### Режим развертывания

```yaml
replicaCount: 1              # Количество реплик pod'ов
mode: statefulSet            # StatefulSet для сохранения состояния

statefulSet:
  clusterMode: false         # Кластерный режим для распределенного скрейпа
  replicationFactor: 1       # Фактор репликации в кластере
```

#### Ресурсы

```yaml
resources:
  limits:
    cpu: 100m                # Максимум CPU (0.1 ядра)
  requests:
    cpu: 20m                 # Минимум CPU (0.02 ядра)
    memory: 100Mi            # Память
```

**Рекомендации по масштабированию**:
- Для малого кластера (< 10 узлов): 100m CPU, 256Mi память достаточно
- Для большого кластера (> 100 узлов): увеличьте до 500m CPU, 1Gi памяти
- Используйте HPA для автоматического масштабирования при необходимости

#### Хранилище

```yaml
persistence:
  enabled: true
  size: 1Gi                  # Размер PVC для WAL
  storageClassName: local-path
```

**Назначение**: WAL (Write-Ahead Log) хранит метрики перед отправкой в Victoria Metrics для гарантии доставки.

#### Сетевая конфигурация

```yaml
service:
  enabled: true
  annotations:
    prometheus.io/scrape: "true"    # Метрики самого vmagent
    prometheus.io/port: "8429"      # Порт метрик

remoteWrite:
- url: "http://vmsingle.monitoring.svc.cluster.local:8428/api/v1/write"
```

**Порты**:
- `8429`: HTTP API, метрики vmagent
- `2003`: Graphite формат (опционально)

#### Горячая перезагрузка

```yaml
annotations:
  configmap.reloader.stakater.com/reload: vmagent-config
```

При изменении ConfigMap pod автоматически перезагружается в течение 30 секунд.

#### TLS для защищенных компонентов

```yaml
extraVolumes:
- name: etcd-tls-volume
  secret:
    secretName: etcd-secrets

extraVolumeMounts:
- name: etcd-tls-volume
  mountPath: /tls/etcd-tls
```

### Конфигурация сбора метрик (scrape-config.yaml)

#### Структура job конфигурации

```yaml
- job_name: component-name
  honor_labels: true              # Сохранять метки из экспортера
  scheme: https                   # HTTP или HTTPS
  tls_config:
    insecure_skip_verify: true    # Пропустить проверку сертификата
    ca_file: /path/to/ca.crt
  
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  
  kubernetes_sd_configs:
  - role: pod                     # pod, endpoints, node, service
    namespaces:
      names: [namespace]
  
  relabel_configs:
  - source_labels: [label1]       # Откуда берем значение
    regex: pattern                # Регулярное выражение для фильтрации
    action: keep                  # keep/drop/replace/labelmap
    target_label: new_label       # На какой лейбл это меняем
```

#### Пример добавления нового job'а

```yaml
# Добавьте в kubernetes-scrape-config.yaml
- job_name: my-service
  kubernetes_sd_configs:
  - role: pod
    namespaces:
      names:
      - my-namespace
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_label_app]
    regex: my-service
    action: keep
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
  - source_labels: [__address__]
    regex: (.+?)(\:\d+)?
    replacement: $1:9090          # Переопределите порт
    action: replace
    target_label: __address__
```

После редактирования `scrape-config.yaml`:
```bash
kubectl apply -f vmagent/scrape-config.yaml
# Pod автоматически перезагружается через ~30 сек благодаря ConfigMap Reloader
```

## Отладка и мониторинг

### Проверка статуса скрейпа

```bash
# Port-forward к vmagent
kubectl port-forward -n monitoring svc/vmagent 8429:8429

# Просмотр активных целей для сбора
curl http://localhost:8429/api/v1/targets | jq .

# Просмотр целей, которые не удались
curl http://localhost:8429/api/v1/targets?state=dropped | jq .

# Метрики самого vmagent
curl http://localhost:8429/metrics | grep vmagent
```

### Проверка логов

```bash
# Следить за логами в реальном времени
kubectl logs -n monitoring -f -l app.kubernetes.io/name=vmagent

# Логи конкретного pod'а
kubectl logs -n monitoring vmagent-0

# Логи JSON формате (при envflag.enable: true и loggerFormat: json)
kubectl logs -n monitoring -l app.kubernetes.io/name=vmagent --tail=100 | jq .
```

### Проверка конфигурации

```bash
# Посмотреть текущую конфигурацию
kubectl get configmap -n monitoring kubernetes-scrape-config -o yaml

# Описать pod для проверки монтирования volume'ов
kubectl describe pod -n monitoring vmagent-0

# Проверить, монтируются ли секреты
kubectl exec -n monitoring vmagent-0 -- ls -la /tls/etcd-tls/
```

### Частые проблемы и решения

#### 1. Pod'ы не запускаются

**Причина**: Отсутствует ConfigMap или Secret

```bash
# Проверьте ConfigMap
kubectl get configmap -n monitoring kubernetes-scrape-config

# Проверьте Secret для TLS
kubectl get secret -n monitoring etcd-secrets
```

**Решение**: Создайте отсутствующие ресурсы:
```bash
kubectl apply -f vmagent/scrape-config.yaml
```

#### 2. Нет подключения к Victoria Metrics

**Признак**: Ошибки в логах о неудаче при отправке метрик

```bash
kubectl logs -n monitoring vmagent-0 | grep "error\|failed"
```

**Решение**: 
- Проверьте, что Victoria Metrics запущена:
  ```bash
  kubectl get svc -n monitoring vmsingle
  kubectl get svc -n monitoring vminsert
  ```
- Проверьте URL в `remoteWrite`:
  ```yaml
  remoteWrite:
  - url: "http://vmsingle.monitoring.svc.cluster.local:8428/api/v1/write"
  ```

#### 3. Целей для сбора не обнаружено

**Проверка**:
```bash
curl http://localhost:8429/api/v1/targets?state=active
# Должен вернуть список активных целей
```

**Решение**:
- Проверьте правила `relabel_configs` в конфигурации
- Убедитесь, что целевые компоненты работают:
  ```bash
  kubectl get pods -n kube-system | grep etcd
  kubectl get pods -n kube-system | grep apiserver
  ```

#### 4. TLS ошибки при подключении к etcd

**Ошибка**: `x509: certificate signed by unknown authority`

**Решение**: Убедитесь, что:
```bash
# Секрет существует
kubectl get secret -n monitoring etcd-secrets -o yaml

# Файлы монтируются в pod
kubectl exec -n monitoring vmagent-0 -- ls -la /tls/etcd-tls/

# Правильные пути в конфигурации etcd job
kubectl get cm -n monitoring kubernetes-scrape-config -o yaml | grep etcd-tls
```

## Масштабирование

### Горизонтальное масштабирование (Multi-instance)

Для масштабирования на несколько инстансов используйте кластерный режим:

```yaml
# vmagent.yaml
replicaCount: 3

statefulSet:
  clusterMode: true
  replicationFactor: 3

# Каждый pod распределит нагрузку между собой
# Каждый job будет обработан одним pod'ом
```

### HorizontalPodAutoscaler

Добавьте автомасштабирование по CPU:

```yaml
hpa:
  enabled: true
  minReplicas: 1
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
```

```bash
# Применить HPA
kubectl autoscale statefulset vmagent \
  --min=1 --max=5 \
  --cpu-percent=70 \
  -n monitoring
```

## Интеграция с системой мониторинга

### В составе стека

vmagent получает метрики из:
- ✅ Kubernetes API Server
- ✅ etcd
- ✅ Kubelet (на каждом узле)
- ✅ cAdvisor (контейнер метрики)
- ✅ Calico (сеть)
- ✅ kube-state-metrics (состояние ресурсов)
- ✅ node-exporter (система хоста)
- ✅ MinIO (S3 хранилище)
- ✅ Любые сервисы с аннотацией `prometheus.io/scrape: "true"`

И отправляет в:
- **vmsingle**: Одиночный Victoria Metrics сервер
- **vmcluster**: Кластер Victoria Metrics (vminsert)

### Проверка end-to-end

```bash
# 1. Проверить что metrics собираются
kubectl port-forward -n monitoring svc/vmagent 8429:8429
curl http://localhost:8429/api/v1/targets | jq '.data.activeTargets | length'

# 2. Проверить что metrics отправляются в storage
kubectl port-forward -n monitoring svc/vmsingle 8428:8428
curl 'http://localhost:8428/api/v1/query?query=up' | jq '.data.result | length'

# 3. Проверить что metrics видны в Grafana
# Откройте http://grafana.dev.local в браузере
```

## Дополнительные ресурсы

- [Victoria Metrics Agent документация](https://docs.victoriametrics.com/vmagent.html)
- [Prometheus Service Discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_configs)
- [Prometheus Relabeling](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config)
- [Victoria Metrics Helm Chart](https://github.com/VictoriaMetrics/helm-charts)
