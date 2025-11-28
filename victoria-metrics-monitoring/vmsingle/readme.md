# vmsingle - Victoria Metrics Single Node

**vmsingle** - это одиночный узел Victoria Metrics для хранения и запроса временных рядов. Это альтернатива кластерной архитектуре для небольших развертываний и разработки.

## Описание

vmsingle - это полнофункциональный сервер Victoria Metrics, который объединяет функции vminsert, vmstorage и vmselect в один бинарный файл. Он идеален для:
- Разработки и тестирования
- Небольших кластеров (< 100 узлов)
- Развертываний с низкими требованиями HA
- Экспериментов с мониторингом

## Архитектура

```
┌────────────────────────────────────────┐
│         vmagent/scraper agents         │
└────────────────────┬───────────────────┘
                     │ HTTP POST
        ┌────────────▼──────────────┐
        │   vmsingle:8428           │
        │  ┌──────────────────────┐ │
        │  │  Write (vminsert)    │ │
        │  │  Storage (vmstorage) │ │
        │  │  Query (vmselect)    │ │
        │  └──────────────────────┘ │
        └────────────┬───────────────┘
                     │ Metrics stored
        ┌────────────▼──────────────┐
        │  PersistentVolume (10Gi)  │
        │  StorageClass: local-path │
        └───────────────────────────┘
```

**Тройная роль**:
- **Write**: Принимает метрики от vmagent
- **Storage**: Хранит временные ряды на диске
- **Query**: Обслуживает PromQL запросы от Grafana

## Структура файлов

```
vmsingle/
├── vmsingle.yaml              # Helm values (текущая конфигурация)
├── vmsingle-default.yaml      # Значения по умолчанию от чарта
├── readme.md                  # Этот файл
```

## Развертывание

### Предварительные требования

1. **Helm 3.x** установлен
2. **Helm репозиторий Victoria Metrics** добавлен:
   ```bash
   helm repo add vm https://victoriametrics.github.io/helm-charts/
   helm repo update
   ```
3. **Storage Class** доступен (например, `local-path`)
4. **Namespace monitoring** создан:
   ```bash
   kubectl create namespace monitoring
   ```

### Установка

```bash
helm upgrade --install vmsingle vm/victoria-metrics-single \
  -f vmsingle/vmsingle.yaml \
  -n monitoring \
  --create-namespace
```

### Проверка статуса

```bash
# Проверить pod
kubectl get pod -n monitoring -l app.kubernetes.io/name=vmsingle

# Просмотреть логи
kubectl logs -n monitoring -l app.kubernetes.io/name=vmsingle -f

# Проверить PersistentVolume
kubectl get pv,pvc -n monitoring | grep vmsingle
```

## Конфигурация

### vmsingle.yaml - Текущие параметры

#### RBAC и ServiceAccount

```yaml
rbac:
  create: false              # RBAC отключен
serviceAccount:
  create: false              # ServiceAccount не создается
```

**Назначение**: Упрощенная конфигурация для разработки. Pod'ы используют встроенную service account токены.

#### Основные параметры сервера

```yaml
server:
  mode: statefulSet          # StatefulSet для сохранения состояния
  fullnameOverride: vmsingle # Сокращенное имя ресурса
```

**StatefulSet обеспечивает**:
- Стабильные имена pod'ов (vmsingle-0)
- Привязка к одному PVC
- Корректный порядок запуска/остановки

#### Retention (период хранения)

```yaml
server:
  retentionPeriod: 1         # 1 месяц
```

**Как рассчитывается**:
- retentionPeriod: 1 = 30 дней
- retentionPeriod: 3 = 90 дней
- retentionPeriod: 12 = 1 год

Фактическое место зависит от сжатия данных (обычно 10-20 раз сжатие).

#### Service и Annotations

```yaml
server:
  service:
    annotations:
      prometheus.io/scrape: "true"  # Включить self-monitoring
      prometheus.io/port: "8428"    # Порт метрик
```

**vmsingle selbst monitored**:
- Собирает метрики о своей работе
- Доступны через `/metrics` endpoint
- Позволяет видеть нагрузку на хранилище

#### Persistent Volume

```yaml
server:
  persistentVolume:
    storageClassName: local-path  # Storage Class
    size: 10Gi                    # Размер диска
```

**Размер хранилища**:
- 10Gi с compression ≈ 100-200 дней данных
- Зависит от количества метрик и частоты сбора
- Старые данные удаляются автоматически по retention

**Storage Classes**:
- `local-path`: Local storage (dev/testing)
- `longhorn-data`: Longhorn distributed storage (HA)
- `ebs-gp3`: AWS EBS (cloud)

#### Ingress

```yaml
server:
  ingress:
    enabled: true
    annotations:
      cert-manager.io/cluster-issuer: ca-issuer
    hosts:
    - name: vmsingle.dev.local
      path: /
    tls:
    - secretName: vmsingle-tls
      hosts:
      - vmsingle.dev.local
```

**Доступ**:
- Через HTTPS по доменному имени `vmsingle.dev.local`
- TLS сертификат автоматически создается cert-manager'ом
- ClusterIssuer `ca-issuer` должна быть предварительно настроена

#### Отключенные компоненты

```yaml
server:
  relabel:
    enabled: false   # Встроенное релабелирование отключено
  scrape:
    enabled: false   # Встроенный скрейпер отключено
```

**Почему отключены**:
- Скрейпинг делает vmagent (отдельный компонент)
- Релабелирование конфигурируется в vmagent
- vmsingle только хранит и выдает данные

#### Закомментированные ресурсы

```yaml
  # resources:
  #   limits:
  #     cpu: 1000m
  #     memory: 1024Mi
  #   requests:
  #     cpu: 500m
  #     memory: 512Mi
```

**Текущее поведение**: No resource limits = "best effort"
- Pod может использовать все доступные ресурсы
- Риск: может съесть память всего кластера
- Рекомендация: раскомментируйте для production

## Порты и API

### Основные порты

| Порт | Назначение | Используется |
|------|-----------|-------------|
| 8428 | HTTP API | Основной (write/query) |
| 8089 | Graphite | Опционально |
| 4242 | OpenTSDB | Опционально |

### Важные endpoints

```bash
# Метрики самого vmsingle
curl http://vmsingle.monitoring.svc.cluster.local:8428/metrics

# Health check
curl http://vmsingle.monitoring.svc.cluster.local:8428/-/healthy

# Info о версии
curl http://vmsingle.monitoring.svc.cluster.local:8428/api/v1/info

# PromQL запрос (через Grafana обычно)
curl 'http://vmsingle.monitoring.svc.cluster.local:8428/api/v1/query?query=up'
```

## Интеграция с системой мониторинга

### Входящие данные (Write)

vmagent отправляет метрики:
```yaml
# vmagent/vmagent.yaml
remoteWrite:
- url: "http://vmsingle.monitoring.svc.cluster.local:8428/api/v1/write"
```

**Write API**:
- Принимает Prometheus remote write формат
- Endpoint: `/api/v1/write`
- Автоматическое сжатие данных

### Исходящие запросы (Query)

Grafana запрашивает метрики:
```yaml
# grafana/grafana.yaml
datasources:
  datasources.yaml:
    datasources:
    - url: http://vmsingle.monitoring.svc.cluster.local:8428
      type: prometheus  # Совместим с Prometheus API
```

**Query API** (Prometheus-compatible):
- `/api/v1/query` - instant queries
- `/api/v1/query_range` - range queries
- PromQL полностью поддерживается

## Отладка и мониторинг

### Проверка хранения данных

```bash
# Port-forward к vmsingle
kubectl port-forward -n monitoring svc/vmsingle 8428:8428

# Список доступных метрик
curl 'http://localhost:8428/api/v1/label/__name__/values' | jq .

# Количество уникальных временных рядов
curl 'http://localhost:8428/api/v1/status/tsdb' | jq .

# Размер данных
curl 'http://localhost:8428/api/v1/status/active_queries' | jq .
```

### Проверка логов

```bash
# Логи в реальном времени
kubectl logs -n monitoring -f -l app.kubernetes.io/name=vmsingle

# Последние 100 строк логов
kubectl logs -n monitoring -l app.kubernetes.io/name=vmsingle --tail=100

# Логи с временем
kubectl logs -n monitoring -l app.kubernetes.io/name=vmsingle --timestamps=true
```

### Мониторинг самого vmsingle

```bash
# Важные метрики
vm_rows:                    # Количество сохраненных точек данных
vm_cache_hits:              # Попадания в кэш
vm_cache_misses:            # Промахи кэша
vm_rows_added_total:        # Общее количество добавленных строк
```

### Частые проблемы

#### 1. Pod не запускается - PVC не создается

**Решение**:
```bash
# Проверьте StorageClass
kubectl get storageclass

# Если local-path не существует, создайте его
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
```

#### 2. Metrics не появляются в Grafana

**Проверьте**:
```bash
# 1. Pod запущен и healthy
kubectl get pod -n monitoring vmsingle-0

# 2. vmagent отправляет данные
kubectl logs -n monitoring -l app.kubernetes.io/name=vmagent | grep write

# 3. Данные в vmsingle
curl 'http://localhost:8428/api/v1/query?query=up' | jq '.data.result | length'
```

#### 3. Диск заполнен (10Gi полный)

**Решение**:
- Уменьшить `retentionPeriod` с 1 месяца до 2 недель
- Или увеличить `persistentVolume.size`

```bash
# Проверить использование диска
kubectl exec -n monitoring vmsingle-0 -- du -sh /victoria-metrics-data
```

## Производительность и оптимизация

### Текущие ограничения

| Параметр | Значение | Примечание |
|----------|----------|-----------|
| Retention | 1 месяц | ~30 дней данных |
| Storage | 10Gi | ~100-200 дней в production |
| Replicas | 1 | Нет HA/redundancy |
| Resources | No limits | Может "съесть" всю память |

### Рекомендации по масштабированию

Если нужна большая емкость хранения:
1. **Увеличить PVC**: `size: 100Gi` или больше
2. **Увеличить retention**: `retentionPeriod: 3` (3 месяца)
3. **Раскомментировать ресурсы**: Для стабильности
4. **Перейти на vmcluster**: Для true HA

## Дополнительные ресурсы

- [Victoria Metrics Single документация](https://docs.victoriametrics.com/single-server-victoriametrics.html)
- [Helm Chart для vmsingle](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-single)
- [PromQL документация](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Remote Write протокол](https://docs.victoriametrics.com/remote-write-specification.html)
