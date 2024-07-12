# Install with helm
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -f ingress/ingress-values.yaml -n ingress-nginx --create-namespace --install 