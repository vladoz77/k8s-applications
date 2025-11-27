# README — VictoriaMetrics Single (vmsingle) Helm Chart

Это пример `values.yaml` для установки **VictoriaMetrics Single Node** (vmsingle) через официальный Helm-чарт VictoriaMetrics (https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-single).

## Описание используемых значений

```yaml
rbac:
  create: false                  # RBAC и ServiceAccount создаём вручную (или через cluster-wide права)

serviceAccount:
  create: false                  # ServiceAccount тоже не создаём в чарте
```

```yaml
server:
  fullnameOverride: vmsingle     # Полное имя ресурсов будет vmsingle (а не vmsingle-victoria-metrics-single)

  persistentVolume:
    storageClass: longhorn-db    # Используем Longhorn с классом longhorn-db
    size: 10Gi                   # Объём диска под данные VM

  extraArgs:
    dedup.minScrapeInterval: 30s # Включаем дедупликацию скрейпов с минимальным интервалом 30 секунд
                                 # Полезно, если несколько Prometheus-ов скрейпят один и тот же vmsingle

  statefulSet:
    service:
      annotations:
        prometheus.io/scrape: "true"   # Разрешаем Prometheus-у скрейпить сам vmsingle
        prometheus.io/port: "8428"

  resources:
    limits:
      cpu: 1000m
      memory: 1024Mi
    requests:
      cpu: 500m
      memory: 512Mi
```

### Ingress (доступ по HTTPS через домен)

```yaml
  ingress:
    enabled: true
    annotations: 
      cert-manager.io/cluster-issuer: ca-issuer   # Автоматически получаем сертификат от вашего ClusterIssuer
    hosts:
    - name: vmsingle.dev.local
      path: /
    tls:
      - secretName: vmsingle-tls
        hosts:
          - vmsingle.dev.local
```

В результате будет доступно:
- `https://vmsingle.dev.local` — веб-интерфейс VictoriaMetrics
- `https://vmsingle.dev.local/select/...` — vmselect
- `https://vmsingle.dev.loca/insert/...` — vminsert
- `https://vmsingle.dev.loca/api/v1/...` — совместимость с Prometheus remote_write/read

## Как установить/обновить

```bash
# Добавляем репозиторий (если ещё не добавлен)
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

# Установка (или upgrade)
helm upgrade --install vmsingle vm/victoria-metrics-single \
  -f values.yaml \
  --namespace monitoring --create-namespace
```

## Полезные проверялки после установки

```bash
# Проверка подов
kubectl -n monitoring get pods -l app.kubernetes.io/name=vmsingle

# Проверка PVC
kubectl -n monitoring get pvc

# Проверка Ingress
kubectl -n monitoring get ingress

# Проверка, что Prometheus может скрейпить vmsingle
kubectl -n monitoring get svc vmsingle -o yaml | grep clusterIP
curl -k https://vmsingle.dev.local/metrics
```

## Рекомендации по продакшену

- Для серьёзных нагрузок лучше использовать `victoria-metrics-cluster` вместо single-node.
- При росте объёма данных увеличьте `persistentVolume.size` и/или включите retention (по умолчанию — всё хранится вечно).
- При необходимости добавить retention можно добавить в `extraArgs`:

```yaml
  extraArgs:
    dedup.minScrapeInterval: 30s
    retentionPeriod: 3y          # хранить данные 3 года
    storageDataPath: /vm-data    # (по умолчанию и так)
```

