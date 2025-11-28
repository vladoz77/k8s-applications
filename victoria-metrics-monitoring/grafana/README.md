# Grafana — мониторинг и визуализация

`grafana` в этом репозитории — Helm values для установки Grafana, используемой как визуализация данных Victoria Metrics.

## Краткое описание

Grafana служит интерфейсом для визуализации метрик, хранящихся в Victoria Metrics (vmsingle / vmcluster). Эта конфигурация рассчитана на локальную/разработческую среду с HTTPS через cert-manager и persistent storage.

## Ключевые значения (из `grafana/grafana.yaml`)

- `image.tag`: `11.4.0` — версия Grafana
- `resources`:
  - `limits.cpu`: `100m`, `limits.memory`: `300Mi`
  - `requests.cpu`: `100m`, `requests.memory`: `200Mi`
- `adminUser`: `admin` (по умолчанию)
- `adminPassword`: `password` (по умолчанию — смените в production)
- `persistence`:
  - `enabled: true`
  - `storageClassName: local-path`
  - `size: 1Gi`
- `securityContext`:
  - `runAsNonRoot: true`, `runAsUser: 472`, `fsGroup: 472`
- `ingress`:
  - `enabled: true`
  - `cert-manager.io/cluster-issuer: ca-issuer`
  - `hosts`: `grafana.dev.local`
  - `tls.secretName`: `grafana-tls`
- `datasources` (по умолчанию):
  - `VictoriaMetrics` (Prometheus-compatible)
  - `url: http://vmsingle.monitoring.svc.cluster.local.:8428`
  - `isDefault: true`

> Примечание: `grafana/grafana.yaml` — это Helm values, не манифест. Применяйте через `helm upgrade --install`.

## Установка (пример)

```bash
helm repo add grafana https://grafana.github.io/helm-charts/
helm repo update
helm upgrade --install grafana grafana/grafana \
  -n monitoring -f grafana/grafana.yaml --create-namespace
```

## Как получить пароль администратора

```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

## Проверка состояния и отладка

- Проверить pod'ы и сервисы

```bash
kubectl get pods,svc -n monitoring -l app.kubernetes.io/name=grafana
```

- Просмотр логов

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=200
```

- Port-forward локально (если нужно открыть UI без DNS)

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
# Откройте http://localhost:3000
```

## Datasource: Victoria Metrics

По умолчанию в `grafana/grafana.yaml` datasource указывает на `vmsingle`:

```yaml
url: http://vmsingle.monitoring.svc.cluster.local.:8428
```

Если вы используете `vmcluster`, замените URL на `vmselect`/`vminsert` адрес или на соответствующий `ClusterIP` сервис в namespace `monitoring`.

Пример обновления значения в Helm values (локально):

```yaml
datasources:
  datasources.yaml:
    datasources:
    - name: VictoriaMetrics
      type: prometheus
      url: http://vmsingle.monitoring.svc.cluster.local:8428
      access: proxy
      isDefault: true
```

Затем примените:

```bash
helm upgrade --install grafana grafana/grafana -n monitoring -f grafana/grafana.yaml
```

## Рекомендации для production

- Смените `adminPassword` на секретный пароль и храните в `Secret` / CI vault.
- Увеличьте `persistence.size` (например, `10Gi` или больше) и используйте HA storage class (`longhorn-data`, `ebs` и т.п.).
- Поднимите ресурсы `requests/limits` (например, `cpu: 500m`, `memory: 1Gi`) для стабильной работы при большом числе дашбордов.
- Отключите `initChownData` или используйте корректную реализацию прав доступа под указанным `securityContext`.
- Ограничьте доступ к Grafana через Ingress/IngressClass с аутентификацией (OAuth/LDAP) в production.

## Частые операции

- Сброс пароля администратора: обновите `grafana/grafana.yaml` или создайте `Secret` с ключом `admin-password` и перезапустите deployment.
- Обновление datasource: правьте `grafana/grafana.yaml` и делайте `helm upgrade`.
- Резервное копирование dashboards: экспортируйте через UI или используйте provisioning/sidecar (в Helm chart есть опции для provisioning из `ConfigMap`/`Secret`).

## Где смотреть в репозитории

- Основной values-файл: `grafana/grafana.yaml`
- Значения по умолчанию (чарты): `grafana/grafana-default-values.yaml`
- ArgoCD приложение: `argocd/grafana.yaml` (если используется)

---


