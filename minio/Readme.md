# install minio
helm install minio  oci://registry-1.docker.io/bitnamicharts/minio -f minio-helm/minio-values.yaml -n minio --create-namespace