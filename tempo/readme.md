# Install helm tempo-distrib
helm install -f tempo-values.yaml  tempo grafana/tempo -n tempo
# install collector
helm install  collector open-telemetry/opentelemetry-collector -f collector-values.yaml -n tempo