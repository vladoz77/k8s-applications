```yaml
# === RBAC и ServiceAccount ===
rbac:
  create: false         # Отключает создание RBAC-ролей (если они уже есть в кластере)
serviceAccount:
  create: false         # Отключает создание ServiceAccount (используется существующий)

# === Основная конфигурация vmsingle ===
server:
  fullnameOverride: vmsingle  # Переопределяет имя StatefulSet и других ресурсов на "vmsingle"
  
  # Настройки постоянного хранилища (PersistentVolume)
  persistentVolume:
    storageClass: longhorn-db  # Использует StorageClass "longhorn-db" (распределенное хранилище)
    size: 10Gi                 # Размер тома для хранения метрик (можно увеличить при росте данных)

  # Дополнительные аргументы командной строки для vmsingle
  extraArgs:
    dedup.minScrapeInterval: 30s  # Минимальный интервал дедупликации метрик (агрегирует дубли за 30 сек)

  # Конфигурация StatefulSet (управление pod'ами)
  statefulSet:
    service:
      annotations:
        prometheus.io/scrape: "true"  # Разрешает сбор метрик Prometheus
        prometheus.io/port: "8428"    # Порт метрик vmsingle

  # Лимиты и запросы ресурсов
  resources:
    limits:
      cpu: 1000m       # Лимит: 1 ядро CPU
      memory: 1024Mi   # Лимит: 1 GiB RAM
    requests:
      cpu: 500m        # Гарантировано: 0.5 ядра CPU
      memory: 512Mi    # Гарантировано: 512 MiB RAM

  # Настройки Ingress (доступ извне)
  ingress:
    enabled: true       # Включает Ingress
    annotations: 
      cert-manager.io/cluster-issuer: ca-issuer  # Автоматическая выдача TLS-сертификата через cert-manager
    hosts:
    - name: vmsingle.dev.local  # Домен для доступа к vmsingle
      path: /
    tls:
      - secretName: vmsingle-tls  # Имя Secret с TLS-сертификатом
        hosts:
          - vmsingle.dev.local    # Домен для сертификата
```

### Разбор ключевых параметров:

1. **Режим работы**:  
   Это конфигурация для **vmsingle** — standalone-режима VictoriaMetrics (все компоненты в одном pod). Подходит для небольших проектов или тестирования.

2. **Хранение данных**:  
   - Используется `longhorn-db` (распределенное хранилище).  
   - Размер тома `10Gi` — минимально для production, лучше мониторить `disk свободное место` (/metrics).  

3. **Дедупликация**:  
   `dedup.minScrapeInterval: 30s` — метрики с одинаковыми labels, пришедшие чаще чем раз в 30 сек, будут дедуплицированы.  

4. **Ресурсы**:  
   - Лимиты: **1 CPU / 1Gi RAM** — хорошо для средней нагрузки.  
   - Requests: **0.5 CPU / 512Mi RAM** — гарантированные ресурсы.  

5. **Безопасность и доступ**:  
   - Ingress с TLS через **cert-manager** (автопродление сертификатов).  
   - Домен `vmsingle.dev.local` — нужно заменить на реальный в production.  

6. **Мониторинг**:  
   - Метрики доступны на порту `8428` (стандартный для vmsingle).  
