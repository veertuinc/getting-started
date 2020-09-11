#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../../shared.bash
[[ -z $(minikube status | grep "host: Running") ]] && echo "You must install minikube first..." && exit 1
if [[ $1 == '--uninstall' ]]; then
  kubectl delete -f namespace.yaml || true
  rm -f namespace.yaml
  exit
fi

cat > namespace.yaml << BLOCK
---
apiVersion: v1
kind: Namespace
metadata:
  name: anka
  labels:
    name: getting-started-examples
BLOCK

kubectl apply -f namespace.yaml
kubectl get namespaces --show-labels
# The next step is to define a context for the kubectl client to work in the namespace
kubectl config set-context anka --namespace=anka \
  --cluster=minikube \
  --user=minikube
kubectl config use-context anka