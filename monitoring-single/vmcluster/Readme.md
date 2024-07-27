helm upgrade --install vmcluster -n monitoring vm/victoria-metrics-cluster -f vmcluster/vmcluster.yaml --create-namespace



You need to update your Prometheus configuration file and add the following lines to it:

prometheus.yml

    remote_write:
      - url: "http://<insert-service>/insert/0/prometheus/"



for example -  inside the Kubernetes cluster:

    remote_write:
      - url: "http://vminsert.monitoring.svc.cluster.local:8480/insert/0/prometheus/"
Read API:


Input this URL field into Grafana

    http://<select-service>/select/0/prometheus/


for example - inside the Kubernetes cluster:

    http://vmselect.monitoring.svc.cluster.local:8481/select/0/prometheus/