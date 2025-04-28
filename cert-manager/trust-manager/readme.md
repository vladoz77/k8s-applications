## Installation

>[!Note]
>See the [installation guide](https://cert-manager.io/docs/trust/trust-manager/installation/) for instructions on how to install trust-manager.


```bash
helm repo add jetstack https://charts.jetstack.io --force-update
```

```bash
helm upgrade trust-manager jetstack/trust-manager \
  --install \
  --namespace cert-manager \
  --wait
```

## Создаем секрет из файлов сертификата etcd
```bash
kubectl create secret generic etcd-ca --from-file=etcd-ca.crt=/etc/kubernetes/pki/etcd/ca.crt -n cert-manager
-n cert-manager
```