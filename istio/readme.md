#  Install Istio base
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm install istio-base istio/base -n istio-system --create-namespace --set defaultRevision=default
helm install istiod istio/istiod -n istio-system -f istio/istiod-values.yaml
#  Install istio-gateway
helm install istio-ingressgateway istio/gateway -n istio-ingress -f istio-ingress-gateway.yaml

# Install kiali
helm repo add kiali https://kiali.org/helm-charts
helm install kiali kiali/kiali-server -n istio-system -f kiali-values.yaml
