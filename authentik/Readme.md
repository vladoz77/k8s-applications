1. Add helm chart
    ```bash
    helm repo add goauthentik https://charts.goauthentik.io/
    ```

2. Create DB and user 
   - db: authentik-db
   - user: authentik
   - password: password

3. Install authentik with helm
    ```bash
    helm upgrade --install authentik goauthentik/authentik -f values.yaml -n auth --create-namespace
    ```

4. After the installation is complete, access authentik
    ```bash
    https://<ingress-host-name>/if/flow/initial-setup/
    ```