# Install master
helm install master opensearch/opensearch -f master.yaml -n es
# Install data
helm install data opensearch/opensearch -f data.yaml -n es
# Install dashboard
helm install dashboard  opensearch/opensearch-dashboards -f dashboard.yaml -n es 
