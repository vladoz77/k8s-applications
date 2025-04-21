## 1. Install minio
```bash
helm install longhorn longhorn/longhorn -f longhorn.yaml -n longhorn-system --create-namespace
```

## 2. Add node labels
```bash
k annotate nodes node01 node02 node03 node.longhorn.io/default-node-tags='["data","db"]'
```

## 3. Add disk to node
```bash
k label nodes node01 node02 node03 node.longhorn.io/create-default-disk='config'
```
```bash
k annotate nodes node01 node.longhorn.io/default-disks-config='[{"name":"data","path":"/mnt/data","allowScheduling":true,"tags":["hdd"]}]'
```
```bash
k annotate nodes node02 node03  node.longhorn.io/default-disks-config='[{"name":"data","path":"/mnt/data","allowScheduling":true,"tags":["hdd"]},{"name":"db","path":"/mnt/db","allowScheduling":true,"tags":["ssd"]}]'
```

## 3. Create secret for minio backup

```bash
echo -n <URL> | base64
echo -n <Access Key> | base64
echo -n <Secret Key> | base64
--------------------------------------------------------
```

## 4. update longhorn

![alt text](image.png)