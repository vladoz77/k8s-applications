1. Install node-exporter 
    ```bash
    helm upgrade --install -n monitoring node-exporter prometheus-community/prometheus-node-exporter -f node-exporter/node-exporter.yaml --create-namespace
    ```

2. Install kube-state-metrics

```bash
helm upgrade --install -n monitoring kube-state-metrics prometheus-community/kube-state-metrics -f kube-state-metrics/kube-state-metrics.yaml --create-namespace
```

3. Install vmsingle or vmcluster

```bash
helm install vmsingle vm/victoria-metrics-single -f vmsingle/vmsingle.yaml -n monitoring --create-namespace
```

```bash
helm install vmcluster -n monitoring vm/victoria-metrics-cluster -f vmcluster/vmcluster.yaml
```
4. Install vmagent

```bash
helm install vmagent vm/victoria-metrics-agent  -f vmagent/vmagent.yaml -n monitoring
```

5. Install grafana

```bash
helm install grafana grafana/grafana -n monitoring -f grafana/grafana.yaml
```

*get password*
```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```




#Install vmalert and alertmanager
k apply -f vmalert-alertmanager/rules
helm install vmalert vm/victoria-metrics-alert  -f vmalert-alertmanager/vmalert-values.yaml    -n monitoring

#Install grafana
helm install grafana grafana/grafana -n monitoring -f grafana/grafana-values.yaml
# get password
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo