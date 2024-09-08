>[!Info]
>https://www.dragonflydb.io/guides/redis-kubernetes
>https://github.com/bitnami/charts/tree/main/bitnami/redis#parameters

1. Add Bitnami repository to Helm:
    ```bash
    helm repo add bitnami https://charts.bitnami.com/bitnami
    ```
2. Update Helm repositories:
    ```bash
    helm repo update
    ```
3. Deploy Redis using custom values:
    ```bash
    helm upgrade --install  redis bitnami/redis -f redis-values.yaml -n redis --create-namespace   
    ```

