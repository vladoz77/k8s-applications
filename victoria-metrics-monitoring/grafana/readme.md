Вот детально описанная конфигурация Grafana с комментариями:

```yaml
# === Версия образа ===
image:
  tag: 11.4.0  # Конкретная версия Grafana (LTS)

# === Ресурсы ===
resources:
  limits:
    cpu: 100m    # Лимит: 0.1 ядра CPU
    memory: 300Mi # Лимит: 300 MiB RAM
  requests:
    cpu: 100m    # Гарантировано: 0.1 ядра CPU
    memory: 200Mi # Гарантировано: 200 MiB RAM

# === Аутентификация ===
adminUser: admin      # Логин администратора (небезопасно в production!)
adminPassword: password  # Пароль администратора (заменить на secret в production!)

# === Хранение данных ===
persistence:
  enabled: true             # Включить постоянное хранилище
  storageClassName: longhorn-data  # Использовать распределенное хранилище
  size: 1Gi                 # Размер тома (рекомендуется 10Gi+ для production)

# === Внешний доступ ===
ingress:
  enabled: true  # Включить Ingress
  annotations: 
    cert-manager.io/cluster-issuer: ca-issuer  # Автоматическая выдача TLS-сертификатов
  path: /        # Базовый путь
  pathType: Prefix
  hosts:
    - grafana.dev.local  # Домен (заменить на production)
  tls:
  - secretName: grafana-tls  # TLS-сертификат
    hosts:
       - grafana.dev.local

# === Источники данных ===
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: VictoriaMetrics
      type: prometheus
      url: http://vmselect.monitoring.svc.cluster.local:8481/select/0/prometheus/
      access: proxy       # Использовать прокси-режим
      isDefault: true     # Источник по умолчанию
      editable: true      # Разрешить редактирование в UI
      
    # Интеграция с Loki (логи)
    - name: loki
      access: proxy
      editable: true
      type: loki
      url: http://loki-gateway.loki.svc
      version: 1
      jsonData:
        derivedFields:    # Связь с Tempo для трейсов
          - datasourceUid: tempo
            matcherRegex: '"trace_id": "(\w+)"'
            name: TraceID
            url: $${__value.raw}
    
    # Интеграция с Tempo (трейсы)
    - name: Tempo
      uid: tempo
      type: tempo
      access: proxy
      url: http://tempo-query-frontend.tempo.svc:3100

# === Провайдеры дашбордов ===
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'grafana-dashboards-kubernetes'
      orgId: 1            # Организация по умолчанию
      folder: 'Kubernetes'  # Папка для дашбордов
      type: file          # Загрузка из файлов
      disableDeletion: true  # Запретить удаление
      editable: true      # Разрешить редактирование
      options:
        path: /var/lib/grafana/dashboards/grafana-dashboards-kubernetes  # Путь к дашбордам

# === Дашборды ===
dashboards:
  grafana-dashboards-kubernetes:
    # Дашборды из репозитория dotdc/grafana-dashboards-kubernetes
    k8s-system-api-server:
      url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-api-server.json
    k8s-system-coredns:
      url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-system-coredns.json
    k8s-views-global:
      url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-global.json
    k8s-views-namespaces:
      url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-namespaces.json
    k8s-views-nodes:
      url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-nodes.json
    k8s-views-pods:
      url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-pods.json
```

### Ключевые особенности:

1. **Интеграция с мониторингом**:
   - VictoriaMetrics как основной источник данных
   - Loki для логов
   - Tempo для трейсов
   - Автоматическая загрузка Kubernetes-дашбордов

2. **Безопасность**:
   - Ingress с TLS (cert-manager)
   - Прокси-режим для источников данных
   - **Важно:** Заменить явные учетные данные на Secrets

3. **Хранение**:
   - Постоянный том через Longhorn
   - Сохранение конфигурации между перезапусками

4. **Проверка работы**:
```bash
# Проверить доступность
curl -I https://grafana.dev.local/api/health

# Проверить загруженные дашборды
curl -s https://grafana.dev.local/api/search | jq .
```