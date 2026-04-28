# MetalLB в Kubernetes

Этот каталог содержит манифесты для базовой настройки `MetalLB` в Kubernetes в режиме `Layer2`.

## Что есть в репозитории

- `manifests/metalb-ip-config.yaml` - пул адресов `IPAddressPool` и `L2Advertisement` для namespace `metallb-system`

## Текущая конфигурация

В файле `manifests/metalb-ip-config.yaml` настроено:

- `IPAddressPool` с именем `first-pool`
- диапазон IP-адресов `192.168.200.250-192.168.200.255`
- `L2Advertisement` для публикации адресов из этого пула

## Требования

- работающий Kubernetes-кластер
- настроенный `kubectl`
- свободный диапазон IP-адресов в вашей локальной сети
- узлы кластера должны быть доступны в одной L2-сети, где MetalLB сможет анонсировать адреса

## Установка

1. Установить `MetalLB` в кластер:

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```

2. Применить локальную конфигурацию IP-пула:

```bash
kubectl apply -f manifests/metalb-ip-config.yaml
```

Если запускать из родительского каталога `k8s-applications`, используйте:

```bash
kubectl apply -f metallb/manifests/metalb-ip-config.yaml
```

## Проверка

Проверить, что компоненты `MetalLB` запущены:

```bash
kubectl get pods -n metallb-system
```

Проверить созданные ресурсы:

```bash
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system
```

## Проверка через Service типа LoadBalancer

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx -w
```

Если всё настроено корректно, сервис получит один из IP-адресов из диапазона `192.168.200.250-192.168.200.255`.

## Важно

- перед применением проверьте, что этот диапазон не используется DHCP или другими устройствами
- при необходимости замените диапазон адресов в `manifests/metalb-ip-config.yaml` на свой
