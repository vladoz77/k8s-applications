1. Install node-exporter 
    ```bash
    helm upgrade --install -n monitoring node-exporter prometheus-community/prometheus-node-exporter -f node-exporter/node-exporter.yaml --create-namespace
    ```




#Install vmsingle
helm install vmsingle vm/victoria-metrics-single -f vmsingle/vm-single-my.yaml -n monitoring --create-namespace

# Or instal vmcluster
helm install vmcluster -n monitoring vm/victoria-metrics-cluster -f vmcluster/vmcluster-values.yaml

#Install vmagent
helm install vmagent vm/victoria-metrics-agent  -f vmagent/vmagent-values.yaml -n monitoring

# Install kube-state-metrics
helm install kube-state-metrics prometheus-community/kube-state-metrics -n monitoring

#Install node exporter
helm install node-exporter prometheus-community/prometheus-node-exporter -n monitoring 

#Install vmalert and alertmanager
k apply -f vmalert-alertmanager/rules
helm install vmalert vm/victoria-metrics-alert  -f vmalert-alertmanager/vmalert-values.yaml    -n monitoring

#Install grafana
helm install grafana grafana/grafana -n monitoring -f grafana/grafana-values.yaml
# get password
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo