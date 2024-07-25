helm install longhorn longhorn/longhorn -f longhorn.yaml -n longhorn-system --create-namespace

# Add node labels
k annotate nodes node01 node.longhorn.io/default-node-tags='["data"]' 
k annotate nodes node02 node.longhorn.io/default-node-tags='["data","db"]' 
k annotate nodes node03 node.longhorn.io/default-node-tags='["db","data"]' 

# Add disk to node
k label nodes node01 node02 node03 node.longhorn.io/create-default-disk='config'
k annotate nodes node01 node.longhorn.io/default-disks-config='[{"name":"data","path":"/mnt/data","allowScheduling":true,"tags":["hdd"]}]'
k annotate nodes node02 node03  node.longhorn.io/default-disks-config='[{"name":"data","path":"/mnt/data","allowScheduling":true,"tags":["hdd"]},{"name":"db","path":"/mnt/db","allowScheduling":true,"tags":["ssd"]}]'

