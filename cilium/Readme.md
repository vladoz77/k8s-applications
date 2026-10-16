# Cilium

Cilium — CNI для Kubernetes на базе eBPF. Конфигурация в этом каталоге включает
замену kube-proxy, выделение IP для `LoadBalancer`, анонс адресов в локальной
сети через L2 и поддержку Kubernetes Gateway API.

## Состав каталога

| Путь | Назначение |
| --- | --- |
| `cilium.yaml` | Переопределения значений Helm-чарта Cilium для этого кластера |
| `cilium-default.yaml` | Сгенерированные значения по умолчанию чарта; справочный файл |
| `manifests/lb-ippool.yaml` | Пул IP-адресов для сервисов типа `LoadBalancer` |
| `manifests/lb-l2-policy.yaml` | Политика L2-анонсов для LoadBalancer IP |
| `manifests/gateway.yaml` | Gateway для проверки Gateway API |
| `tests/lb-test.yaml` | Тестовый Pod и сервис `LoadBalancer` |
| `tests/gateway-apps.yaml` | Тестовые приложения и их сервисы |
| `tests/gateway-multi-route.yaml` | HTTP-маршруты к тестовым приложениям |

`cilium-default.yaml` сформирован из upstream-чарта. Для установки используйте
`cilium.yaml`, а не этот файл.

## Требования

- Рабочий Kubernetes-кластер и `kubectl` с настроенным контекстом.
- Helm 3.
- Совместимые версии Kubernetes, Cilium и Gateway API CRD.
- Для L2-анонсов — узлы в общей L2-сети и свободные IP-адреса из указанного пула.
- Для замены kube-proxy — доступный Cilium адрес API-сервера Kubernetes.

> **Перед установкой проверьте `cilium.yaml`.** Параметр `k8sServiceHost`
> задан как `172.10.10.11`, а `k8sServicePort` — `6443`. Укажите реальный
> адрес API-сервера, доступный с каждого узла кластера. Неверное значение при
> `kubeProxyReplacement: true` может помешать запуску Cilium и сетевой работе
> кластера.

Также проверьте, что диапазон `172.10.10.200–172.10.10.250` в
`manifests/lb-ippool.yaml` свободен и доступен в вашей сети. При необходимости
измените адреса и регулярное выражение интерфейса `^eth[0-9]+` в
`manifests/lb-l2-policy.yaml` под имена интерфейсов узлов.

## Установка

Если кластер использует другой CNI или kube-proxy, заранее спланируйте
миграцию: `kubeProxyReplacement: true` меняет сетевую конфигурацию кластера.
Для нового кластера установку Cilium обычно выполняют до запуска рабочих
нагрузок. Не удаляйте существующий CNI до проверки плана миграции.

Добавьте репозиторий Helm и установите выбранную совместимую версию чарта.
Версия чарта не закреплена в этом каталоге; для воспроизводимых установок
перед установкой задайте `CILIUM_VERSION` на выбранную версию и передайте её
через `--version`.

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm upgrade --install cilium cilium/cilium \
  --namespace cilium-system \
  --create-namespace \
  --version "$CILIUM_VERSION" \
  --values cilium.yaml
```

Параметры `gatewayAPI.enabled: true` требуют установленных Gateway API CRD.
До создания Gateway убедитесь, что CRD версии, поддерживаемой выбранной
версией Cilium, установлены в кластере. В конфигурации включено создание
`GatewayClass` с именем `cilium`.

Проверьте состояние установки:

```bash
kubectl get pods -n cilium-system
kubectl get nodes
cilium status --namespace cilium-system
```

Команда `cilium status` требует установленного Cilium CLI. Если CLI не
установлен, проверьте состояние компонентов командами `kubectl`.

## Проверка LoadBalancer и L2-анонсов

Создайте пул адресов и политику анонсов:

```bash
kubectl apply -f manifests/lb-ippool.yaml
kubectl apply -f manifests/lb-l2-policy.yaml
```

Разверните тестовый сервис и дождитесь назначения ему адреса:

```bash
kubectl apply -f tests/lb-test.yaml
kubectl get pod lb-test -o wide
kubectl get svc lb-test-svc -o wide
kubectl get ciliuml2announcementpolicies
kubectl get ciliumloadbalancerippools
```

В выводе `kubectl get svc lb-test-svc` проверьте поле `EXTERNAL-IP`. С узла,
который имеет сетевой доступ к адресу, проверьте HTTP-ответ:

```bash
curl http://<EXTERNAL-IP>/
```

Замените `<EXTERNAL-IP>` на назначенный адрес. Если адрес не назначен,
проверьте соответствие IP-пула вашей сети, наличие свободных адресов и
состояние Cilium Operator. Если адрес назначен, но сервис недоступен,
проверьте L2-связность и совпадение интерфейсов с политикой анонсов.

## Проверка Gateway API

Установите совместимые Gateway API CRD, если они ещё не установлены, затем
создайте Gateway и тестовые приложения с маршрутами:

```bash
kubectl apply -f manifests/gateway.yaml
kubectl apply -f tests/gateway-apps.yaml
kubectl apply -f tests/gateway-multi-route.yaml
```

Все тестовые ресурсы создаются в текущем namespace `kubectl` (обычно `default`).
`HTTPRoute` разрешает подключение к Gateway только из того же namespace.

Проверьте статус Gateway и маршрутов:

```bash
kubectl get gatewayclass
kubectl get gateway cilium-gateway
kubectl get httproute
kubectl get pods,svc
```

Возьмите адрес из `kubectl get gateway cilium-gateway` (или из созданного для
Gateway LoadBalancer-сервиса) и проверьте маршрутизацию, подставив этот адрес
вместо `GATEWAY_IP`:

```bash
curl --resolve app1.test.local:80:GATEWAY_IP http://app1.test.local/
curl --resolve app2.test.local:80:GATEWAY_IP http://app2.test.local/
```

В ответе должны быть страницы `App1` и `App2`. Если Gateway или маршрут не
переходит в состояние `Programmed`/`Accepted`, проверьте состояние Cilium,
наличие Gateway API CRD и совпадение namespace, имени Gateway и `parentRefs`.

## Удаление тестовых ресурсов

Удалите тестовые приложения и Gateway:

```bash
kubectl delete -f tests/gateway-multi-route.yaml --ignore-not-found
kubectl delete -f tests/gateway-apps.yaml --ignore-not-found
kubectl delete -f manifests/gateway.yaml --ignore-not-found
kubectl delete -f tests/lb-test.yaml --ignore-not-found
```

Пул и политику L2 можно удалить, когда кластер больше не использует
LoadBalancer IP из этого пула:

```bash
kubectl delete -f manifests/lb-l2-policy.yaml
kubectl delete -f manifests/lb-ippool.yaml
```

Удаление Cilium из работающего кластера может нарушить сетевую связность и
доступность сервисов. Перед удалением чарта спланируйте замену CNI и убедитесь,
что кластер сможет продолжить работу без Cilium.