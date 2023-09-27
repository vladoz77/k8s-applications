# Install master
helm install master opensearch/opensearch -f master-values.yaml -n es
# Install data
helm install data opensearch/opensearch -f data-values.yaml -n es
# Install dashboard
helm install dashboard  opensearch/opensearch-dashboards -f dashboard-values.yaml -n es 
