# Install with helm
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -f ingress.yaml  -n ingress-nginx --create-namespace --install