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
helm upgrade --install vmsingle vm/victoria-metrics-single -f vmsingle/vmsingle.yaml -n monitoring --create-namespace
```

```bash
helm upgrade --install vmcluster -n monitoring vm/victoria-metrics-cluster -f vmcluster/vmcluster.yaml --create-namespace
```
4. Install vmagent

```bash
helm upgrade --install vmagent vm/victoria-metrics-agent  -f vmagent/vmagent.yaml -n monitoring --create-namespace
```

5. Install alertmanager and vmrules

```bash
k apply -f vmalert-alertmanager/rules
helm upgrade --install vmrules vm/victoria-metrics-alert  -f vmrules/vmrules.yaml  -n monitoring --create-namespace
kubectl apply -f alertmanager/manifests
```

5. Install grafana

```bash
helm upgrade --install grafana grafana/grafana -n monitoring -f grafana/grafana.yaml --create-namespace
```

*get grafana password*
```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

