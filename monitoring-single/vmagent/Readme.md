# Создаем секрет из файлов сертификата для k8s
kubectl create secret generic etcd-ca \
--from-file /etc/kubernetes/pki/etcd/server.crt \
--from-file /etc/kubernetes/pki/etcd/server.key \
-n monitoring

# Создаем секрет из файлов сертификата для k3s
kubectl create secret generic etcd-ca \
--from-file /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
--from-file /var/lib/rancher/k3s/server/tls/etcd/server-ca.key \
-n monitoring

# Config calico metrics
# Enable metrics
kubectl patch felixconfiguration default --type merge --patch '{"spec":{"prometheusMetricsEnabled": true}}'
kubectl patch installation default --type=merge -p '{"spec": {"typhaMetricsPort":9093}}'

# Create service for metrucs
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: calico-felix-metrics
  namespace: calico-system
spec:
  selector:
    k8s-app: calico-node
  ports:
  - port: 9091
    targetPort: 9091
EOF