#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../../shared.bash
REPLICAS=3
[[ -z $(minikube status | grep "host: Running") ]] && echo "You must install minikube first..." && exit 1
if [[ $1 == '--uninstall' ]]; then
  kubectl delete -f etcd.yaml || true &
  kubectl delete -f etcd-sc-pv.yaml || true &
  sleep 10
  kubectl delete pvc -l app=etcd
  rm -f etcd*yaml
  docker exec -ti minikube bash -c "rm -rf /data/etcd/*"
  exit
fi
cat > etcd-sc-pv.yaml << BLOCK
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: etcd-0-data
spec:
  storageClassName: local-storage
  capacity:
    storage: 500Mi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/etcd"
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: etcd-1-data
spec:
  storageClassName: local-storage
  capacity:
    storage: 500Mi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/etcd"
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: etcd-2-data
spec:
  storageClassName: local-storage
  capacity:
    storage: 500Mi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/etcd"
    type: DirectoryOrCreate
BLOCK
kubectl apply -f etcd-sc-pv.yaml
sleep 5
cat > etcd.yaml << BLOCK
---
apiVersion: v1
kind: Service
metadata:
  name: etcd-client
spec:
  type: LoadBalancer
  ports:
    - name: etcd-client
      port: 2379
      protocol: TCP
      targetPort: 2379
  selector:
    app: etcd
---
apiVersion: v1
kind: Service
metadata:
  name: etcd
spec:
  clusterIP: None
  ports:
    - port: 2379
      name: client
    - port: 2380
      name: peer
  selector:
    app: etcd
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  labels:
    app: etcd
  name: etcd
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: etcd
  serviceName: etcd
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: etcd
      name: etcd
    spec:
      containers:
        - name: etcd
          image: quay.io/coreos/etcd:latest
          imagePullPolicy: IfNotPresent
          env:
            - name: ETCDCTL_API
              value: "3"
          command:
            - /bin/sh
            - -c
            - |
              sleep 10 # needed to let DNS start properly
              PEERS=""
              for podNum in \$(seq 0 $((REPLICAS - 1))); do
                  PEERS="\${PEERS}\${PEERS:+,}etcd-\${podNum}=http://etcd-\${podNum}.etcd:2380"
              done
              exec etcd --debug --name \${HOSTNAME} \\
                --listen-peer-urls http://0.0.0.0:2380 \\
                --listen-client-urls http://0.0.0.0:2379 \\
                --advertise-client-urls http://\${HOSTNAME}.etcd:2379 \\
                --initial-advertise-peer-urls http://\${HOSTNAME}.etcd:2380 \\
                --initial-cluster-token etcd-cluster-1 \\
                --initial-cluster \${PEERS} \\
                --initial-cluster-state new \\
                --data-dir /var/run/etcd/\${HOSTNAME} \\
                --auto-compaction-retention 1
          ports:
            - containerPort: 2379
              name: client
              protocol: TCP
            - containerPort: 2380
              name: peer
              protocol: TCP
          volumeMounts:
            - mountPath: /var/run/etcd
              name: etcd-data
      restartPolicy: Always
  updateStrategy:
    rollingUpdate:
      partition: 0
    type: RollingUpdate
  volumeClaimTemplates:
    - metadata:
        name: etcd-data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 100Mi
        storageClassName: local-storage
        volumeMode: Filesystem
BLOCK
kubectl apply -f etcd.yaml 
echo "==================================================================="
echo "- etcd data is stored inside of the minikube (kube node) docker container under /data/etcd"
echo "- the etcd cluster requires more than 50% of the instances to be up. If you lose 1 pod out of the 3, it will be fine. If you lose 2, the cluster will fail."
echo
echo "Testing ETCD can be done by running 'minikube tunnel' and then executing:"
echo 
echo 'watch -n 1 "curl -s http://127.0.0.1:2379/health; echo && kubectl exec -it etcd-0 -- /bin/sh -c \"RND=\\\$RANDOM; echo \\\$RND; ETCDCTL_API=3; etcdctl member list && etcdctl --endpoints=http://etcd-2.etcd:2379 put \\\$RND bar && etcdctl get \\\$RND\""'
echo
echo "Once the watch is running, kubectl delete pods etcd-1 and confirm that the put and get is still functional."

# watch -n 2 "kubectl get svc && kubectl get pods -o wide && echo ==================== && kubectl logs --tail 10 etcd-0 && echo ==================== && kubectl logs --tail 10 etcd-1 && echo ==================== && kubectl logs --tail 10 etcd-2 && echo ==================== && kubectl logs --tail 10 etcd-3"