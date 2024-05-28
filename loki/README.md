1. Install promtail
k apply -f promtail  -n loki

2. Install loki
helm install loki grafana/loki -n loki --create-namespace -f loki-single-s3.yaml 