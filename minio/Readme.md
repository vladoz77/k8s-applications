# install minio standalone
```bash
helm install minio  oci://registry-1.docker.io/bitnamicharts/minio -f minio-helm/minio-standalone.yaml  -n minio --create-namespace
```