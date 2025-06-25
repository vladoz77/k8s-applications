# VMRules - Управление правилами алертинга и записи для VictoriaMetrics

## Назначение

VMRules (на базе VMAlert) - компонент для:
- Оценки recording rules (постоянных выражений)
- Генерации алертов на основе метрик
- Отправки алертов в Alertmanager
- Хранения правил в ConfigMaps

## Особенности конфигурации

### Основные параметры
- **Репликация**: 2 экземпляра для отказоустойчивости
- **Ресурсы**: Минимальные требования (15m CPU, 25M RAM)
- **Интервал оценки**: 1 минута
- **Источник данных**: VictoriaMetrics (vmselect)
- **Хранение правил**: В ConfigMaps, смонтированных как тома

### Правила алертинга
Правила организованы по категориям:
1. `alertmanager-rules` - правила для мониторинга Alertmanager
2. `node-rules` - правила для мониторинга узлов
3. `kubernetes-rules` - правила для Kubernetes
4. `minio-rules` - правила для MinIO

### Сетевые настройки
- **Сервис**: Порт 8880, аннотации для Prometheus
- **Ingress**: HTTPS через cert-manager, домен vmrules.dev.local

## Установка

1. Создайте ConfigMaps с правилами:
```bash
kubectl create configmap alertmanager-rules --from-file=./rules/alertmanager/
kubectl create configmap node-rules --from-file=./rules/node/
kubectl create configmap kubernetes-rules --from-file=./rules/kubernetes/
kubectl create configmap minio-rules --from-file=./rules/minio/
```

2. Установите через Helm:

```bash
helm upgrade --install vmrules vm/victoria-metrics-alert \
  -n monitoring \
  -f values.yaml
```
