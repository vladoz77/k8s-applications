# Victoria Metrics в Kubernetes

Victoria Metrics - это быстрая, экономичная и масштабируемая система мониторинга и хранения временных рядов, совместимая с Prometheus.

## Особенности

- Высокая производительность и эффективное хранение данных
- Совместимость с Prometheus API
- Поддержка многих форматов данных (Prometheus, InfluxDB, OpenTSDB, Graphite)
- Кластерная версия для горизонтального масштабирования
- Низкие требования к ресурсам
- Высокая степень сжатия данных

## Компоненты

1. **Victoria Metrics Server** - основной компонент для хранения и обработки метрик
2. **vmagent** - агент для сбора метрик
3. **vmalert** - компонент для обработки правил алертинга
4. **vmauth** - компонент аутентификации
5. **Grafana** - визуализация метрик

## Установка

### Предварительные требования

- Kubernetes кластер
- Helm 3.x
- kubectl

### Добавление Helm репозитория

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update
```

### Установка через ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: victoria-metrics
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://victoriametrics.github.io/helm-charts/
    targetRevision: <version>
    chart: victoria-metrics-k8s-stack
    helm:
      values: |
        # Ваши значения конфигурации
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Конфигурация

### Основные параметры

```yaml
# values.yaml
vmcluster:
  enabled: true
  replicaCount: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi

vmagent:
  enabled: true
  resources:
    requests:
      cpu: 200m
      memory: 512Mi

vmalert:
  enabled: true
  resources:
    requests:
      cpu: 200m
      memory: 512Mi

grafana:
  enabled: true
  adminPassword: <your-password>
```

### Настройка сбора метрик

```yaml
# serviceScrape example
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMServiceScrape
metadata:
  name: example-scrape
spec:
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
  selector:
    matchLabels:
      app: your-app
```

## Доступ к интерфейсам

- Victoria Metrics UI: `http://<your-domain>/vm`
- Grafana: `http://<your-domain>/grafana`
- vmalert: `http://<your-domain>/vmalert`

## Мониторинг основных метрик

### Kubernetes метрики
- CPU использование
- Memory использование
- Disk I/O
- Network I/O
- Pod статусы

### Системные метрики
- Node Exporter метрики
- System load
- Filesystem использование
- Network статистика

## Алертинг

### Пример правила алерта

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMRule
metadata:
  name: example-alert
spec:
  groups:
    - name: example
      rules:
        - alert: HighCPUUsage
          expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            description: "CPU usage is above 80%"
            summary: "High CPU usage detected"
```

## Резервное копирование

Для резервного копирования данных Victoria Metrics рекомендуется использовать встроенный механизм снапшотов:

```bash
curl -X POST http://<vm-server>:8428/snapshot/create
```

## Обслуживание

### Очистка старых данных

Victoria Metrics автоматически удаляет старые данные согласно настройке `retentionPeriod`. По умолчанию это 1 месяц.

### Проверка состояния

```bash
kubectl get vmclusters
kubectl get vmagents
kubectl get vmalerts
```

## Troubleshooting

### Частые проблемы

1. Недостаточно ресурсов
   - Проверьте лимиты ресурсов
   - Мониторьте использование CPU и памяти

2. Проблемы с подключением
   - Проверьте сетевые политики
   - Проверьте endpoints и service discovery

3. Высокое потребление диска
   - Проверьте настройки retention
   - Оптимизируйте scrape intervals

## Полезные ссылки

- [Официальная документация Victoria Metrics](https://docs.victoriametrics.com/)
- [Helm Charts](https://github.com/VictoriaMetrics/helm-charts)
- [Operator documentation](https://docs.victoriametrics.com/operator/)