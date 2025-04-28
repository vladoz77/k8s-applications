```yaml
# Setting simple scalable deployment mode - оптимальный режим для средних/крупных инсталляций
deploymentMode: SimpleScalable

loki:
  image:
    registry: docker.io  # Официальный Docker registry
    repository: grafana/loki  # Официальный образ Loki от Grafana
    tag: 3.4.2  # Конкретная версия для стабильности

  # Disable multi-tenant support - упрощенная конфигурация без мультитенантности
  auth_enabled: false  # В продакшне следует включить!

  # Common config - общие настройки кластера
  commonConfig:
    replication_factor: 3  # Высокая отказоустойчивость данных

  # Ingester config - параметры обработки входящих логов
  ingester:
    chunk_idle_period: 2h  # Чанк закрывается после 2 часов неактивности
    chunk_target_size: 1536000  # ~1.5MB - оптимальный размер для баланса производительности
    max_chunk_age: 2h  # Максимальное время жизни чанка
    chunk_encoding: snappy  # Эффективное сжатие данных

  # limits config - защита от перегрузки системы
  limits_config:
    reject_old_samples: true  # Блокировка старых логов
    reject_old_samples_max_age: 168h  # Максимальный возраст логов (1 неделя)
    max_query_parallelism: 12  # Общий параллелизм = max_concurrent * querier pods
    split_queries_by_interval: 15m  # Разделение длинных запросов на части
    per_stream_rate_limit: 5MB  # Лимит на поток
    per_stream_rate_limit_burst: 20MB  # Кратковременные всплески
    ingestion_rate_mb: 20  # Общий лимит приема данных
    ingestion_burst_size_mb: 30  # Общий burst-лимит
    max_entries_limit_per_query: 100000  # Защита от "тяжелых" запросов
    allow_structured_metadata: true  # Поддержка структурированных метаданных

  # querier config - параметры выполнения запросов
  querier:
    engine:
      max_look_back_period: 300  # Максимальный период поиска (в днях)
    max_concurrent: 4  # Параллельные запросы на pod

  pattern_ingester:
    enabled: true  # Анализ паттернов в логах - полезно для обнаружения аномалий

  # ruler config - управление правилами и алертами
  rulerConfig:
    storage:
      type: local  # Локальное хранение правил (можно заменить на конфигмап)
      local:
        directory: /etc/loki/rules
    alertmanager_url: http://alertmanager.monitoring.svc.cluster.local:9093  # Интеграция с Alertmanager
    wal:  # Write-Ahead Log для надежности
      dir: /var/loki/loki-wal
    remote_write:  # Отправка метрик в VictoriaMetrics
      enabled: true
      clients:
        victoria-metrics:
          name: vm
          url: http://vminsert.monitoring.svc.cluster.local:8480/insert/0/prometheus/

  # S3 backend storage configuration - объектное хранилище для данных
  storage:
    bucketNames:
      chunks: loki  # Имя бакета для чанков
    type: s3  # Использование S3-совместимого хранилища
    s3:
      endpoint: minio.minio.svc.cluster.local:9000  # Внутренний MinIO
      secretAccessKey: password  # В продакшне заменить на secret!
      accessKeyId: admin  # В продакшне заменить на secret!
      s3ForcePathStyle: true  # Необходимо для MinIO
      insecure: true  # Для тестовой среды без TLS

  # Storage Schema - схема хранения данных
  schemaConfig:
    configs:
    - from: 2024-04-01  # Версия схемы с указанной даты
      store: tsdb  # Использование TSDB для эффективного хранения
      index:
        prefix: loki_index_  # Префикс индексов
        period: 24h  # Период ротации индексов
      object_store: s3  # Хранилище объектов
      schema: v13  # Версия схемы Loki

  # Optional querier configuration - кэширование результатов запросов
  query_range:
    align_queries_with_step: true  # Выравнивание временных интервалов
    results_cache:
      cache:
        default_validity: 12h  # Время жизни кэша
        memcached_client:
          addresses: 'dns+result-cache-memcached.loki.svc.cluster.local:11211'  # Memcached для кэша
          timeout: 500ms  # Таймаут запросов

  # Structured loki configuration - альтернативный формат конфигурации
  structuredConfig:
    chunk_store_config:
      chunk_cache_config:  # Кэширование чанков
        memcached:
          batch_size: 256  # Размер батча
          parallelism: 10  # Степень параллелизма
        memcached_client:
          addresses: 'dns+chunk-cache-memcached.loki.svc.cluster.local:11211'  # Memcached для чанков

# Configuration for the write - настройки компонента записи
write:
  replicas: 3  # 3 реплики для отказоустойчивости
  persistence:
    size: 5Gi  # Размер диска
    storageClass: longhorn-data  # Использование Longhorn
  service:
    annotations:
      prometheus.io/port: '3100'  # Экспорт метрик для Prometheus
      prometheus.io/scrape: 'true'

# Configuration for the read - настройки компонента чтения
read:
  replicas: 3  # Масштабируемость запросов
  persistence:
    size: 5Gi
    storageClass: longhorn-data
  service:
    annotations:
      prometheus.io/port: '3100'
      prometheus.io/scrape: 'true'

# Configuration for the backend - настройки бэкенда
backend:
  replicas: 2  # Меньше реплик, так как менее критичный компонент
  persistence:
    size: 5Gi
    storageClass: longhorn-data
  service:
    annotations:
      prometheus.io/port: '3100'
      prometheus.io/scrape: 'true'
  extraVolumeMounts:  # Монтирование правил
  - name: rules-volume
    mountPath: /etc/loki/rules/fake/loki-rules.yaml
    subPath: loki-rules.yaml
  - name: rules-volume
    mountPath: /etc/loki/rules/fake/loki-alert.yaml
    subPath: loki-alert.yaml
  extraVolumes:  # Источники правил
  - name: rules-volume
    configMap:
      name: loki-rules
  - name: alert-volume
    configMap:
      name: loki-alert

# Configuration for the gateway - API gateway для Loki
gateway:
  enabled: true  # Включен для балансировки нагрузки
  replicas: 2  # 2 реплики для отказоустойчивости

# Disable cache config - кэширование вынесено в structuredConfig
chunksCache:
  enabled: false
resultsCache:
  enabled: false

# Disable mino installation - используется внешний MinIO
minio:
  enabled: false

# Disable self-monitoring - мониторинг Loki средствами Loki
monitoring:
  selfMonitoring:
    enabled: false
    grafanaAgent:
      installOperator: false

# Disable helm-test - отключение тестов Helm
test:
  enabled: false

# Disable Loki-canary - инструмент мониторинга работы Loki
lokiCanary:
  enabled: false
```

