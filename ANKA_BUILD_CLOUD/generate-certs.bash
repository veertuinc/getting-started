#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
ORGANIZATION="Veertu Inc"
ORG_UNIT="Developer Relations"
CA_CN="Anka Root CA"
CONTROLLER_CN="Anka Controller"
mkdir -p $CERT_DIRECTORY
cd $CERT_DIRECTORY
# Cleanup
sudo security delete-certificate -c "$CA_CN" /Library/Keychains/System.keychain || true
rm -f anka-controller-*.pem
rm -f anka-*.pem
rm -f anka-node-*.pem
echo "[Creating $CA_CN Root CA]"
openssl req -new -nodes -x509 -sha256 -days 365 -keyout anka-ca-key.pem -out anka-ca-crt.pem -subj "/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$CA_CN"
echo "[Adding $CA_CN Root CA to System Keychain]"
sudo security add-trusted-cert -d -k /Library/Keychains/System.keychain anka-ca-crt.pem # Add the Root CA to the System keychain so the Root CA is trusted
echo "[Creating $CONTROLLER_CN Cert]"
export CONTROLLER_SERVER_IP=${CONTROLLER_SERVER_IP:-"127.0.0.1"}
openssl genrsa -out anka-controller-key.pem 4096
openssl req -new -nodes -sha256 -key anka-controller-key.pem -out anka-controller-csr.pem -subj "/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$CONTROLLER_CN" -reqexts SAN -extensions SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nextendedKeyUsage = serverAuth\nsubjectAltName=IP:$CONTROLLER_SERVER_IP,DNS:$CLOUD_CONTROLLER_ADDRESS,DNS:$CLOUD_REGISTRY_ADDRESS,DNS:host.docker.internal"))
openssl x509 -req -days 365 -sha256 -in anka-controller-csr.pem -CA anka-ca-crt.pem -CAkey anka-ca-key.pem -CAcreateserial -out anka-controller-crt.pem -extfile <(echo subjectAltName = IP:$CONTROLLER_SERVER_IP,DNS:$CLOUD_CONTROLLER_ADDRESS,DNS:$CLOUD_REGISTRY_ADDRESS,DNS:host.docker.internal)
echo "[The following should be sha256WithRSAEncryption]"
openssl x509 -text -noout -in anka-controller-crt.pem | grep Signature
echo "[Generating Node Certificate]"
OLDIFS="$IFS"
IFS=$'\n'
# $hostname is used if you're running Anka CLI on the machine you're running this script. Otherwise, change it to have the hostnames or IPs of the node that's running your Anka CLI and VMs
NODE_NAMES=(
  $(hostname)
)
for NODE_NAME in "${NODE_NAMES[@]}"; do
  openssl genrsa -out anka-node-$NODE_NAME-key.pem 4096
  openssl req -new -sha256 -key anka-node-$NODE_NAME-key.pem -out anka-node-$NODE_NAME-csr.pem -subj "/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$NODE_NAME"
  openssl x509 -req -days 365 -sha256 -in anka-node-$NODE_NAME-csr.pem -CA anka-ca-crt.pem -CAkey anka-ca-key.pem -CAcreateserial -out anka-node-$NODE_NAME-crt.pem
  echo "sudo ankacluster join https://${CLOUD_CONTROLLER_ADDRESS}:$CLOUD_CONTROLLER_PORT --cert $CERT_DIRECTORY/anka-node-$NODE_NAME-crt.pem --cert-key $CERT_DIRECTORY/anka-node-$NODE_NAME-key.pem --cacert $CERT_DIRECTORY/anka-ca-crt.pem"
  echo "curl -v https://${CLOUD_CONTROLLER_ADDRESS}:$CLOUD_CONTROLLER_PORT/api/v1/status --cert $CERT_DIRECTORY/anka-node-$NODE_NAME-crt.pem --key $CERT_DIRECTORY/anka-node-$NODE_NAME-key.pem"
done
IFS=$OLDIFS

function create-cert(){
  NAME=$1
  NAME_UPPERCASE="$(tr '[:lower:]' '[:upper:]' <<< ${NAME:0:1})${NAME:1}"
  echo "[Creating $NAME_UPPERCASE Cert]"
  openssl genrsa -out anka-$NAME-key.pem 4096
  openssl req -new -sha256 -key anka-$NAME-key.pem -out anka-$NAME-csr.pem -subj "/O=$ORGANIZATION/OU=$ORG_UNIT/CN=$NAME_UPPERCASE"
  openssl x509 -req -days 365 -sha256 -in anka-$NAME-csr.pem -CA anka-ca-crt.pem -CAkey anka-ca-key.pem -CAcreateserial -out anka-$NAME-crt.pem
}

create-cert "jenkins"
echo "Add the certificate to the Credentials section of Jenkins, then use it in your Configure Clouds > Anka Cloud section with https://"
create-cert "gitlab"
create-cert "teamcity"
echo
echo "Certs are stored in $CERT_DIRECTORY"