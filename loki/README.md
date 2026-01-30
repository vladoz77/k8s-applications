1. Install alloy

```bash
helm upgrade --install --namespace loki alloy grafana/alloy --values alloy/alloy.yaml 
```


2. Install loki

```bash
 helm upgrade --install loki grafana/loki -n loki --create-namespace -f loki/loki-simplescalable.yaml    
 ```

3. Install memcached

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install -n loki chunk-cache bitnami/memcached 
helm upgrade --install -n loki result-cache bitnami/memcached 
```