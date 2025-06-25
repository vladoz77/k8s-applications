# VMAgent Deployment Configuration

VMAgent - это легковесный агент для сбора и отправки метрик в VictoriaMetrics.

## Основные характеристики

- **Кластерный режим**: Развертывание в виде StatefulSet с 3 репликами
- **Масштабируемость**: Поддержка горизонтального масштабирования
- **Надежность**: Анти-аффинити подов для распределения по разным нодам
- **Безопасность**: Поддержка TLS для защищенного сбора метрик

## Конфигурация

### Основные параметры

- **Ресурсы**: 
  - Лимиты: 100m CPU, 200Mi Memory
  - Запросы: 20m CPU, 100Mi Memory
- **Хранилище**: 1Gi PersistentVolume с классом `longhorn-data`
- **Remote Write**: Отправка метрик в `vminsert` сервис

### Собираемые метрики

Конфигурация включает сбор метрик для:

1. **Основные компоненты Kubernetes**:
   - etcd
   - kube-apiserver
   - kube-controller-manager
   - kube-scheduler
   - kube-proxy
   - kubelet
   - cAdvisor

2. **Дополнительные компоненты**:
   - Calico
   - kube-state-metrics
   - node-exporter

3. **Автоматическое обнаружение**:
   - Сервисы с аннотацией `prometheus.io/scrape: "true"`
   - Pod'ы с аннотацией `prometheus.io/scrape: "true"`

## Развертывание

1. Убедитесь, что в кластере доступны:
   - Секрет `etcd-ca` с TLS сертификатами
   - ConfigMap `trust-ca` с CA bundle
   - StorageClass `longhorn-data`

2. Настройте параметры в `values.yaml`:
   - Измените `remoteWrite.url` при необходимости
   - Настройте ресурсы в соответствии с нагрузкой
   - При необходимости измените параметры persistent volume

3. Примените конфигурацию через Helm:

```bash
helm upgrade --install vmagent victoria-metrics/vmagent -f values.yaml
```

4.  Создаем секрет из файлов сертификата

```bash
kubectl create secret generic etcd-ca \
--from-file /etc/kubernetes/pki/etcd/server.crt \
--from-file /etc/kubernetes/pki/etcd/server.key \
-n monitoring
```