## Install Vertical Pod Autoscaler
1. Add helm repo
    ```bash
    helm repo add fairwinds-stable https://charts.fairwinds.com/stable
    ```

2. Install helm-chart with values
   ```bash
   helm install vpa fairwinds-stable/vpa -n vpa -f vpa-values.yaml --create-namespace        
   ```

## Install goldilocks

1. Install helm with values
   ```bash
   helm upgrade --install goldilocks -n vpa fairwinds-stable/goldilocks -f goldilocks-values.yaml
   ```

## Use goldilocks

1. Add label to namespace for create vpa
   ```bash
   kubectl label ns default goldilocks.fairwinds.com/enabled=true
   ```
2. VPA Update Mode
   ```bash
   kubectl label ns default goldilocks.fairwinds.com/vpa-update-mode="auto"
   ```
