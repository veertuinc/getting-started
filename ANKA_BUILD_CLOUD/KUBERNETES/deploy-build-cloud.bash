#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../../shared.bash
[[ -z $(minikube status | grep "host: Running") ]] && echo "You must install minikube first..." && exit 1
if [[ $1 == '--uninstall' ]]; then
  kubectl delete -f build-cloud-lb-ss.yaml || true &
  kubectl delete -f build-cloud-pv.yaml || true &
  sleep 10
  kubectl delete pvc -l app=build-cloud
  rm -f build-cloud*.yaml
  while true; do
    read -p "Do you wish to delete the /data/build-cloud containing all of your VM Templates and Tags (no suggested) [y/n]: " yn
    case $yn in
        [Yy]*) docker exec -ti minikube bash -c "rm -rf /data/build-cloud"; break;;
        [Nn]*) echo "Not deleting any data"; break;;
    esac
  done
  exit
fi
[[ -z $(kubectl get pod etcd-0 | grep etcd-0) ]] && echo "You must setup etcd first..." && exit 1
# Set Hosts
modify_hosts $CLOUD_CONTROLLER_ADDRESS &>/dev/null
modify_hosts $CLOUD_REGISTRY_ADDRESS &>/dev/null
cat > build-cloud-pv.yaml << BLOCK
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: build-cloud-0-data
spec:
  storageClassName: local-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/build-cloud"
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: build-cloud-1-data
spec:
  storageClassName: local-storage
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data/build-cloud"
    type: DirectoryOrCreate
BLOCK
kubectl apply -f build-cloud-pv.yaml 
sleep 5
cat > build-cloud-lb-ss.yaml << BLOCK
---
apiVersion: v1
kind: Service
metadata:
  name: build-cloud-controller
spec:
  type: LoadBalancer
  ports:
    - name: build-cloud-controller
      port: 8090
      protocol: TCP
      targetPort: 80
  selector:
    app: build-cloud
---
apiVersion: v1
kind: Service
metadata:
  name: build-cloud-registry
spec:
  type: LoadBalancer
  ports:
    - name: build-cloud-registry
      port: 8089
      protocol: TCP
      targetPort: 8089
  selector:
    app: build-cloud
---
apiVersion: v1
kind: Service
metadata:
  name: build-cloud
spec:
  clusterIP: None
  ports:
    - port: 80
      name: controller
    - port: 8089
      name: registry
  selector:
    app: build-cloud
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  labels:
    app: build-cloud
  name: build-cloud
spec:
  replicas: 2
  selector:
    matchLabels:
      app: build-cloud
  serviceName: build-cloud
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        app: build-cloud
      name: build-cloud
    spec:
      containers:
        - name: controller
          env:
            - name: ANKA_STANDLONE
              value: "false"
            - name: ANKA_LISTEN_ADDR
              value: ":80"
            - name: ANKA_ANKA_REGISTRY
              value: "http://anka.registry:8089"
            - name: ANKA_LOCAL_ANKA_REGISTRY
              value: "http://localhost:8089"
            - name: ANKA_ETCD_ENDPOINTS
              value: "http://etcd-client:2379"
          image: veertu/anka-build-cloud-controller:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
              name: controller
              protocol: TCP
          command: ["/bin/bash", "-c", "anka-controller"]
        - name: registry
          image: veertu/anka-build-cloud-registry:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8089
              name: registry
              protocol: TCP
          volumeMounts:
            - mountPath: /mnt/vol
              name: build-cloud-data
      restartPolicy: Always
  updateStrategy:
    rollingUpdate:
      partition: 0
    type: RollingUpdate
  volumeClaimTemplates:
    - metadata:
        name: build-cloud-data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
        storageClassName: local-storage
        volumeMode: Filesystem
BLOCK
kubectl apply -f build-cloud-lb-ss.yaml
echo "============================================================================="
echo "Controller UI:  $URL_PROTOCOL$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT"
echo "Registry:       $URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
echo "- registry data is stored inside of the minikube (kube node) docker container under /data/build-cloud (you can get into it with 'minikube ssh')"
echo "- Accessing the dashboard and registry requires that you first run 'minikube tunnel --cleanup; minikube tunnel'. Once it's running, http://anka.controller:8090 and the registry http://anka.registry:8089 are now available."

# watch -n 2 "kubectl get svc && kubectl get pods -o wide && echo ==================== && kubectl logs --tail 10 build-cloud-0 -c controller && echo ==================== && kubectl logs --tail 10 build-cloud-0 -c registry && echo ==================== && kubectl logs --tail 10 build-cloud-1 -c controller && echo ==================== && kubectl logs --tail 10 build-cloud-1 -c registry && kubectl logs --tail 10 etcd-0"