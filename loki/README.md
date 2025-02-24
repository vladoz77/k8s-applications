1. Install promtail
k apply -f promtail  -n loki

2. Install loki
helm install loki grafana/loki -n loki --create-namespace -f loki-single-s3.yaml 

3. Install memcached
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install -n loki chunk-cache bitnami/memcached 
helm install -n loki result-cache bitnami/memcached 