# Gateway API + Envoy Gateway

## Шаг 1. Установить CRD Gateway API

```bash
kubectl apply --server-side=true -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
```

Проверка:

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

## Шаг 2. Установить CRD Envoy Gateway

```bash
kubectl apply --server-side=true -f \
  https://github.com/envoyproxy/gateway/releases/download/v1.7.2/envoy-gateway-crds.yaml
```

## Шаг 3. Установить Envoy Gateway

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.2 \
  -n envoy-gateway-system \
  --create-namespace \
  --skip-crds
```

Проверка:

```bash
kubectl get pods -n envoy-gateway-system
```

## Шаг 4. Создать GatewayClass

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway-class
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF

kubectl get gatewayclass
```

Ожидаемый класс из этого репозитория: `envoy-gateway-class`.

## Шаг 5. Создать Gateway

### Вариант A. Только HTTP

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-gateway
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy-gateway-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
EOF

kubectl get gateway -n envoy-gateway-system
kubectl describe gateway envoy-gateway -n envoy-gateway-system
```

Этот вариант:

- создаёт `Gateway` `envoy-gateway`
- поднимает только listener `http`
- подходит для базовой проверки `HTTPRoute`

### Вариант B. HTTP + HTTPS

Установим Cert-Manager через helm и настроим автоматический выпуск TLS-сертификата для HTTPS listener. Этот вариант более полный и демонстрирует возможности TLS termination через `Gateway`.

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.2 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

Также установим trust-manager для автоматической загрузки CA bundle в кластере:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade trust-manager jetstack/trust-manager \
  --install \
  --namespace cert-manager \
  --wait
```

Установим self-signed CA и ClusterIssuer:

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}

---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ca
  namespace: cert-manager
spec:
  isCA: true
  subject:
    organizations:
      - "Vlad's homelab"
    organizationalUnits:
      - "Home lab"
    localities:
      - "Ryazan"
    countries:
      - "RU"
  commonName: ca
  secretName: ca-secret
  privateKey:
    encoding: PKCS8
    algorithm: RSA
    size: 4096
    rotationPolicy: Always
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io

---
# Create CA Issuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: ca-secret

---
# CA bundle
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: trust-ca
spec:
  sources:
  - secret:
      name: ca-secret
      key: tls.crt
  target:
    configMap:
      key: trust-bundle.pem
EOF
```

Проверка bootstrap CA:

```bash
kubectl get clusterissuer selfsigned-issuer ca-issuer
kubectl wait --for=condition=Ready certificate/ca -n cert-manager --timeout=5m
kubectl get certificate ca -n cert-manager
kubectl get secret ca-secret -n cert-manager
kubectl describe certificate ca -n cert-manager
kubectl get bundle trust-ca
kubectl describe bundle trust-ca
```

Создадим `Gateway` с HTTP и HTTPS listeners, используя `ca-issuer` для автоматического выпуска сертификата:

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-gateway
  namespace: envoy-gateway-system
  annotations:
    cert-manager.io/cluster-issuer: ca-issuer
spec:
  gatewayClassName: envoy-gateway-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.dev.local"
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - name: envoy-tls-secret
EOF

kubectl get gateway -n envoy-gateway-system
kubectl describe gateway envoy-gateway -n envoy-gateway-system
```

Этот вариант:

- создаёт `Gateway` `envoy-gateway`
- поднимает listeners `http` и `https`
- использует аннотацию `cert-manager.io/cluster-issuer: ca-issuer`
- ожидает TLS secret `envoy-tls-secret`

Важно:

- для HTTP-only сценария используйте `envoy-gateway.yaml`
- для HTTPS сценария используйте `envoy-gateway-https.yaml`
- `HTTPRoute` в этом репозитории ссылаются на `Gateway` с именем `envoy-gateway`
- в HTTPS-варианте listener `https` настроен на hostname `*.dev.local`

Получить адрес Gateway:

```bash
kubectl get gateway envoy-gateway -n envoy-gateway-system \
  -o jsonpath='{.status.addresses[0].value}'
echo
```

Если у локального кластера нет внешнего адреса, посмотрите сервисы Envoy Gateway:

```bash
kubectl get svc -n envoy-gateway-system
```

И используйте `port-forward` к сервису data plane.

## Шаг 6. Развернуть demo-приложение

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: demo-apps
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v1
  namespace: demo-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
      version: v1
  template:
    metadata:
      labels:
        app: demo
        version: v1
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args:
        - "-text=Hello from App v1"
        ports:
        - containerPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v2
  namespace: demo-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
      version: v2
  template:
    metadata:
      labels:
        app: demo
        version: v2
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args:
        - "-text=Hello from App v2"
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app-v1
  namespace: demo-apps
spec:
  selector:
    app: demo
    version: v1
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app-v2
  namespace: demo-apps
spec:
  selector:
    app: demo
    version: v2
  ports:
  - port: 80
    targetPort: 5678
EOF

kubectl get pods -n demo-apps
kubectl get svc -n demo-apps
```

Будут созданы:

- `app-v1`
- `app-v2`

Оба сервиса слушают `80` и отвечают через `hashicorp/http-echo`.

## Шаг 7. Настроить базовую маршрутизацию

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-route
  namespace: demo-apps
spec:
  parentRefs:
  - name: envoy-gateway
    namespace: envoy-gateway-system
  hostnames:
  - "demo.dev.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: app-v1
      port: 80
EOF

kubectl get httproute -n demo-apps
kubectl describe httproute demo-route -n demo-apps
```

Маршрут из репозитория использует hostname `demo.dev.local`.

Для локальных тестов можно добавить запись в `/etc/hosts`, чтобы обращаться к маршруту по имени, без явного заголовка `Host`.

Если у `Gateway` есть реальный IP:

```bash
GATEWAY_IP=$(kubectl get gateway envoy-gateway -n envoy-gateway-system \
  -o jsonpath='{.status.addresses[0].value}')

echo "$GATEWAY_IP demo.dev.local" | sudo tee -a /etc/hosts
getent hosts demo.dev.local
```

Если вы тестируете через `port-forward` на локальную машину, используйте `127.0.0.1`:

```bash
echo "127.0.0.1 demo.dev.local" | sudo tee -a /etc/hosts
```

Проверка:

```bash
GATEWAY_IP=$(kubectl get gateway envoy-gateway -n envoy-gateway-system \
  -o jsonpath='{.status.addresses[0].value}')

curl -H "Host: demo.dev.local" "http://$GATEWAY_IP/"
curl "http://demo.dev.local/"
```

Ожидаемый ответ:

```text
Hello from App v1
```

## Шаг 8. Дополнительные варианты маршрутизации

### Split traffic

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-route-split
  namespace: demo-apps
spec:
  parentRefs:
  - name: envoy-gateway
    namespace: envoy-gateway-system
  hostnames:
  - "demo.dev.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: app-v1
      port: 80
      weight: 90
    - name: app-v2
      port: 80
      weight: 10
EOF
```

Маршрут направляет:

- `90%` трафика на `app-v1`
- `10%` трафика на `app-v2`

Важно:

- если одновременно существуют `demo-route` и `demo-route-split`, они конфликтуют, потому что у них одинаковые `parentRefs`, `hostnames` и `matches`
- в таком случае запросы для `demo.dev.local` с путем `/` заберёт более старый `HTTPRoute`, то есть обычно `demo-route`
- чтобы в этом примере реально заработал split `90/10`, удалите базовый маршрут `demo-route` и оставьте только `demo-route-split`

```bash
kubectl delete httproute demo-route -n demo-apps
kubectl get httproute -n demo-apps
```

Проверка:

```bash
for i in {1..20}; do
  curl -s -H "Host: demo.dev.local" "http://$GATEWAY_IP/"
done
```

### Маршрутизация по заголовку

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-route-headers
  namespace: demo-apps
spec:
  parentRefs:
  - name: envoy-gateway
    namespace: envoy-gateway-system
  hostnames:
  - "demo.dev.local"
  rules:
  - matches:
    - headers:
      - name: version
        value: v2
    backendRefs:
    - name: app-v2
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: app-v1
      port: 80
EOF
```

Проверка:

```bash
curl -H "Host: demo.dev.local" "http://$GATEWAY_IP/"
curl -H "Host: demo.dev.local" -H "version: v2" "http://$GATEWAY_IP/"
```

Ожидаемо:

- без заголовка ответит `app-v1`
- с `version: v2` ответит `app-v2`

## Шаг 9. HTTPS через cert-manager

Для автоматического выпуска TLS-сертификата под `Gateway` в этом репозитории используется `cert-manager`.

Важно:

- в [envoy-gateway-https.yaml](https://github.com/vladoz77/k8s-applications/blob/main/GatewayAPI/manifests/envoy-gateway-https.yaml) уже есть annotation `cert-manager.io/cluster-issuer: ca-issuer`
- HTTPS listener использует `certificateRefs.name: envoy-tls-secret`
- cert-manager создаст `Secret` в том же namespace, где находится `Gateway`, то есть в `envoy-gateway-system`
- пример ниже использует self-signed CA, это удобно для lab/dev, но не для публичного production


### 9.1. Применить Gateway c HTTPS listener

После готовности `ca-issuer` можно применить или обновить `Gateway`:

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-gateway-https
  namespace: envoy-gateway-system
  annotations:
    cert-manager.io/cluster-issuer: ca-issuer
spec:
  gatewayClassName: envoy-gateway-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.dev.local"
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - name: envoy-tls-secret
EOF

kubectl describe gateway envoy-gateway -n envoy-gateway-system
```

### 9.4. Применить HTTPS route

```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-route-https
  namespace: demo-apps
spec:
  parentRefs:
  - name: envoy-gateway-https
    namespace: envoy-gateway-system
    sectionName: https
  hostnames:
  - "demo-https.dev.local"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: app-v1
      port: 80
EOF

kubectl describe httproute demo-route-https -n demo-apps
```
Так как изменили hostname на `demo-https.dev.local`, не забудьте добавить его в `/etc/hosts`:

```bash
echo "$GATEWAY_IP demo-https.dev.local" | sudo tee -a /etc/hosts
getent hosts demo-https.dev.local
```


### 9.5. Проверить выпуск сертификата

Проверка созданных ресурсов:

```bash
kubectl get certificate -n envoy-gateway-system
kubectl get secret envoy-tls-secret -n envoy-gateway-system
kubectl describe secret envoy-tls-secret -n envoy-gateway-system
kubectl get secret envoy-tls-secret -n envoy-gateway-system -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Если сертификат не появляется, проверьте события и логи:

```bash
kubectl describe gateway envoy-gateway -n envoy-gateway-system
kubectl get certificate -n envoy-gateway-system
kubectl describe certificate -n envoy-gateway-system
kubectl logs -n cert-manager deployment/cert-manager
kubectl logs -n cert-manager deployment/trust-manager
```

### 9.6. Проверить HTTPS-запрос

Так как используется self-signed CA, обычный клиент не будет доверять сертификату автоматически.

Быстрый тест:

```bash
GATEWAY_IP=$(kubectl get gateway envoy-gateway-https -n envoy-gateway-system \
  -o jsonpath='{.status.addresses[0].value}')

curl -k https://demo-https.dev.local 
```

Проверка с доверенным root CA без `-k`:

```bash
kubectl get secret ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ca.crt
curl --cacert /tmp/ca.crt https://demo-https.dev.local
openssl s_client -connect "${GATEWAY_IP}:443" -servername demo.dev.local -CAfile /tmp/ca.crt </dev/null
```

Если хотите доверять сертификату системно, добавьте root CA в trust store вашей машины или используйте отдельный публично доверенный issuer.

### 9.7. Если хотите использовать свой пример с `Issuer`

Ваш вариант с namespace-scoped `Issuer` тоже валиден, но только если:

- `Issuer` находится в том же namespace, что и `Gateway`
- либо сам `Gateway` перенесён в namespace, где создан `Issuer`

Для текущего репозитория удобнее и корректнее использовать `ClusterIssuer`, потому что `Gateway` уже размещён в `envoy-gateway-system`.

## Полезные проверки

```bash
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
kubectl get pods -n envoy-gateway-system
kubectl get pods -n demo-apps
```

Логи контроллера:

```bash
kubectl logs -n envoy-gateway-system deployment/envoy-gateway
```

## Частые проблемы

### Gateway не получает адрес

Для `kind`, `minikube` и других локальных кластеров это нормально. Используйте `port-forward` или отдельный load balancer, например `MetalLB`.

### HTTPRoute не применяется к Gateway

Проверьте:

- корректный `parentRefs`
- namespace `envoy-gateway-system`
- hostname `demo.dev.local`
- статус route через `kubectl describe httproute -n demo-apps`

### HTTPS не поднимается

Проверьте:

- существует ли секрет `envoy-tls-secret`
- совпадает ли hostname с `*.dev.local`
- привязался ли `httproute-https.yaml` к listener `https`

## Источники

- Статья-основа: https://medium.com/faun/kubernetes-gateway-api-a-complete-step-by-step-setup-guide-397d0ff5375f
- Gateway API releases: https://github.com/kubernetes-sigs/gateway-api/releases
- Envoy Gateway install docs: https://gateway.envoyproxy.io/latest/install/install-helm/
- Envoy Gateway releases: https://github.com/envoyproxy/gateway/releases
- cert-manager Gateway docs: https://cert-manager.io/docs/usage/gateway/
- cert-manager SelfSigned docs: https://cert-manager.io/docs/configuration/selfsigned/
- cert-manager releases: https://github.com/cert-manager/cert-manager/releases
