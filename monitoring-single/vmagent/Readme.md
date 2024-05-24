# Создаем секрет из файлов сертификата
kubectl create secret generic etcd-ca \
--from-file /etc/kubernetes/pki/etcd/server.crt \
--from-file /etc/kubernetes/pki/etcd/server.key \
-n monitoring