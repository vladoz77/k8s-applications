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