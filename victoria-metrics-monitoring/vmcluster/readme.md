# Victoria Metrics Cluster Helm Configuration

This document describes the configuration for Victoria Metrics Cluster deployment using Helm.

## Components Configuration

### vmselect
- **Role**: Query component that processes user requests
- **Replicas**: 2 (scales up to 5 based on CPU usage)
- **Replication Factor**: 3
- **Resources**: 
  - Requests: 100m CPU, 128Mi Memory
  - Limits: 200m CPU, 256Mi Memory
- **HPA**: Enabled (target CPU utilization 70%)

### vminsert
- **Role**: Data ingestion component
- **Replicas**: 2 (scales up to 5 based on CPU usage)
- **Replication Factor**: 3
- **Resources**:
  - Requests: 100m CPU, 128Mi Memory
  - Limits: 200m CPU, 256Mi Memory
- **HPA**: Enabled (target CPU utilization 70%)

### vmstorage
- **Role**: Persistent storage component
- **Replicas**: 3 (recommended for high availability)
- **Retention**: 30 days
- **Storage**:
  - Class: longhorn-db
  - Size: 8Gi per pod
  - Mount path: /storage
- **Anti-Affinity**: Pods distributed across different nodes
- **Resources**:
  - Requests: 100m CPU, 500Mi Memory
  - Limits: 200m CPU, 1000Mi Memory

## Important Notes

1. The configuration uses pod anti-affinity rules for vmstorage to ensure high availability.
2. All components expose Prometheus metrics on their respective ports.
3. The replication factor is set to 3 for data redundancy.
4. Horizontal Pod Autoscaler is configured for vmselect and vminsert components.
5. Persistent storage is required for vmstorage pods to retain metrics data.

## Customization

To modify the configuration:
1. Edit the `vmcluster.yaml` values file
2. Adjust parameters as needed (replicas, resources, retention period, etc.)
3. Commit changes to your Git repository
4. Argo CD will automatically sync the changes (if auto-sync is enabled)

## Monitoring

All components are annotated for Prometheus scraping:
- vmselect: port 8481
- vminsert: port 8480
- vmstorage: port 8482