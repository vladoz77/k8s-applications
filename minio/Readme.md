1. Install standalone minio

```bash
helm upgrade --install minio  oci://registry-1.docker.io/bitnamicharts/minio -f minio-helm/minio-standalone.yaml -n minio
```

2. Install distributed minio

```bash
helm upgrade --install minio  oci://registry-1.docker.io/bitnamicharts/minio -f minio-helm/minio-distributed.yaml -n minio
```