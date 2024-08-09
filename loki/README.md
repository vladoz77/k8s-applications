1. Install promtail
k apply -f promtail  -n loki

2. Install loki
helm install loki grafana/loki -n loki --create-namespace -f loki-single-s3.yaml 

3. Install memcached
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install -n loki chunk-cache bitnami/memcached -f memcache/chunk-cache.yaml
helm install -n loki query-cache bitnami/memcached -f memcache/query-cache.yaml
helm install -n loki index-cache bitnami/memcached -f memcache/index-cache.yaml