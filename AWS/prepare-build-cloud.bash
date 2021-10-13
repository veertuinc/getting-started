#!/bin/bash
set -eo pipefail
AWS_PAGER=
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"
. ../shared.bash
. ./.shared.bash
[[ -z $(command -v jq) ]] && error "JQ is required. You can install it with brew install jq."
warning "This script is tested with AWS CLI v2.2.9. If your version differs (mostly a concern for older versions), there is no guarantee it will function as expected!${COLOR_NC}" && sleep 2
cleanup() {
  [[ "${INSTANCE_ID}" != null ]] && aws_execute "ec2 terminate-instances \
    --instance-ids \"${INSTANCE_ID}\"" && \
      while [[ "$(aws_execute -r -s "ec2 describe-instances --instance-ids \"${INSTANCE_ID}\"" | jq -r '.Reservations[0].Instances[0].State.Name')" != 'terminated' ]]; do
        echo "Instance terminating... Waiting to release the Elastic IP..."
        sleep 50
      done

  [[ "${ELASTIC_IP_ID}" != null ]] && aws_execute "ec2 release-address \
    --allocation-id \"${ELASTIC_IP_ID}\""

  [[ "${SECURITY_GROUP_ID}" != null ]] && aws_execute "ec2 delete-security-group \
    --group-id \"${SECURITY_GROUP_ID}\" \
    --group-name \"${AWS_NONUNIQUE_LABEL}\""
}

echo "${COLOR_CYAN}==============================================${COLOR_NC}"
echo "${COLOR_CYAN}]] Creating and setting up Anka Build Cloud [[${COLOR_NC}"
echo "${COLOR_CYAN}==============================================${COLOR_NC}"

[[ "$(uname)" != "Darwin" ]] && echo "${COLOR_YELLOW}WARNING: We cannot guarantee this script with function on modern non-Darwin/MacOS shells (bash or zsh)${COLOR_NC}" && sleep 2
# Ensure aws cli is installed
[[ -z "$(command -v aws)" ]] && error "aws command not found; https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html${COLOR_NC}"
if $AWS_USE_PROFILE; then
  [[ ! -e "${AWS_CRED_FILE_LOCATION}" ]] && error "No credentials file found in ${AWS_CRED_FILE_LOCATION}..."
  # Ensure --profile is set for cli
  aws_obtain_profile
fi
# Ensure region is set for cli
aws_obtain_region
# Ensure the key pair for instance creation is set
aws_obtain_key_pair
echo "] AWS User: ${COLOR_GREEN}$(aws_execute -s -r "iam get-user | jq -r '.User.UserName, \"|\", .User.UserId' | xargs")${COLOR_NC}";
echo "${COLOR_CYAN}==============================================${COLOR_NC}"

# Collect all existing ids and instances
SECURITY_GROUP="$(aws_execute -r -s "ec2 describe-security-groups --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"")"
SECURITY_GROUP_ID="$(echo "${SECURITY_GROUP}" | jq -r '.SecurityGroups[0].GroupId')"
ELASTIC_IP="$(aws_execute -r -s "ec2 describe-addresses --filter \"Name=tag:purpose,Values=${AWS_UNIQUE_LABEL}\"")"
ELASTIC_IP_ID="$(echo "${ELASTIC_IP}" | jq -r '.Addresses[0].AllocationId')"
ELASTIC_IP_IP="$(echo "${ELASTIC_IP}" | jq -r '.Addresses[0].PublicIp')"
INSTANCE="$(aws_execute -r -s "ec2 describe-instances --filters \"Name=instance-state-name,Values=running\" \"Name=tag:purpose,Values=${AWS_UNIQUE_LABEL}\"")"
INSTANCE_ID="$(echo "${INSTANCE}" | jq -r '.Reservations[0].Instances[0].InstanceId')"
ELASTIC_IP_ASSOC="$(aws_execute -r -s "ec2 describe-addresses --filters \"Name=tag:purpose,Values=${AWS_UNIQUE_LABEL}\"")"
ELASTIC_IP_ASSOC_ID="$(echo "${ELASTIC_IP_ASSOC}" | jq -r '.Addresses[0].AssociationId')"
CONTROLLER_ADDRESSES="$(aws_execute -r -s "ec2 describe-addresses --filter \"Name=tag:purpose,Values=${AWS_UNIQUE_LABEL}\"")"
ANKA_CONTROLLER_IP="$(echo "${CONTROLLER_ADDRESSES}" | jq -r '.Addresses[0].PrivateIpAddress')"

# Used to prevent removal if anka node still exists and hasn't been disjoined
DEDICATED_HOST="$(aws_execute -r -s "ec2 describe-hosts --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"")"
DEDICATED_HOST_ID="$(echo "${DEDICATED_HOST}" | jq -r '.Hosts[0].HostId')"
ANKA_INSTANCE="$(aws_execute -r -s "ec2 describe-instances --filters \"Name=host-id,Values=${DEDICATED_HOST_ID}\" \"Name=instance-state-name,Values=running\" \"Name=tag:purpose,Values=${AWS_UNIQUE_LABEL}\"")"
ANKA_INSTANCE_ID="$(echo "${ANKA_INSTANCE}" | jq -r '.Reservations[0].Instances[0].InstanceId')"
[[ "${ANKA_INSTANCE_ID}" != null ]] && echo "Cloud has joined nodes... Please run prepare-anka-node.bash --delete first!" && exit 1

# Cleanup
if [[ "$1" == "--delete" ]]; then
  cleanup
  exit
fi

# Create security group
if [[ "${SECURITY_GROUP_ID}" == null ]]; then
  SECURITY_GROUP=$(aws_execute -r "ec2 create-security-group \
    --description \"$AWS_NONUNIQUE_LABEL\" \
    --group-name \"$AWS_NONUNIQUE_LABEL\" \
    --tag-specifications \"ResourceType=security-group,Tags=[{Key=Name,Value="$AWS_NONUNIQUE_LABEL"},{Key=purpose,Value=${AWS_NONUNIQUE_LABEL}}]\"")
  SECURITY_GROUP_ID="$(echo "${SECURITY_GROUP}" | jq -r '.GroupId')"
  echo " - Created Security Group: ${COLOR_GREEN}${SECURITY_GROUP_ID}${COLOR_NC}"
else
  echo " - Using existing Security Group: ${COLOR_GREEN}${SECURITY_GROUP_ID} | ${AWS_UNIQUE_LABEL}${COLOR_NC}"
fi

## Add IP to security group
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port ${CLOUD_CONTROLLER_PORT} --cidr ${AWS_AUTHORIZE_CIDR} &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port ${CLOUD_REGISTRY_PORT} --cidr ${AWS_AUTHORIZE_CIDR} &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr ${AWS_AUTHORIZE_CIDR} &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port ${CLOUD_CONTROLLER_PORT} --source-group $SECURITY_GROUP_ID &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port ${CLOUD_REGISTRY_PORT} --source-group $SECURITY_GROUP_ID &>/dev/null || true"
echo " - Added ${HOST_IP} to Security Group ${SECURITY_GROUP_ID} (${CLOUD_CONTROLLER_PORT}, ${CLOUD_REGISTRY_PORT}, 22)"

# Create Elastic IP
if [[ "${ELASTIC_IP_ID}" == null ]]; then
  ELASTIC_IP=$(aws_execute -r "ec2 allocate-address \
    --domain \"vpc\" \
    --tag-specifications \"ResourceType=elastic-ip,Tags=[{Key=Name,Value="$AWS_UNIQUE_LABEL"},{Key=purpose,Value=${AWS_UNIQUE_LABEL}}]\"")
  ELASTIC_IP_ID="$(echo "${ELASTIC_IP}" | jq -r '.AllocationId')"
  ELASTIC_IP_IP="$(echo "${ELASTIC_IP}" | jq -r '.PublicIp')"
  echo " - Created Elastic IP: ${COLOR_GREEN}${ELASTIC_IP_ID} | ${ELASTIC_IP_IP}${COLOR_NC}"
else
  echo " - Using existing Elastic IP: ${COLOR_GREEN}${ELASTIC_IP_ID} | ${ELASTIC_IP_IP}${COLOR_NC}"
fi

# Create EC2 instance for Cloud
if [[ "${INSTANCE_ID}" == null ]]; then
  ## Get latest AMI ID (regardless of region)
  AMI_ID="$(aws_execute -r -s "ec2 describe-images \
    --owners \"amazon\" \
    --filters \"Name=name,Values=${AWS_BUILD_CLOUD_AMI_NAME}\" \"Name=state,Values=available\" \
    --query \"sort_by(Images, &CreationDate)[-1].[ImageId]\" \
    --output \"text\"")"
  INSTANCE=$(aws_execute -r "ec2 run-instances \
    --image-id \"${AMI_ID}\" \
    --instance-type \"${AWS_BUILD_CLOUD_INSTANCE_TYPE}\" \
    --security-group-ids \"${SECURITY_GROUP_ID}\" \
    --key-name \"${AWS_KEY_PAIR_NAME}\" \
    --count 1 \
    --block-device-mappings \"{\\\"DeviceName\\\": \\\"/dev/xvda\\\",\\\"VirtualName\\\": \\\"anka-build-cloud\\\",\\\"Ebs\\\": { \\\"VolumeType\\\": \\\"io2\\\", \\\"Iops\\\": 20000, \\\"VolumeSize\\\": 100 }}\" \
    --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value="$AWS_UNIQUE_LABEL Anka Build Cloud Controller and Registry"},{Key=purpose,Value=${AWS_UNIQUE_LABEL}}]\"")
  INSTANCE_ID="$(echo "${INSTANCE}" | jq -r '.Instances[0].InstanceId')"
  ANKA_CONTROLLER_IP="$(echo "${INSTANCE}" | jq -r '.Instances[0].PrivateIpAddress')"
  while [[ "$(aws_execute -r -s "ec2 describe-instance-status --instance-ids \"${INSTANCE_ID}\"" | jq -r '.InstanceStatuses[0].InstanceState.Name')" != 'running' ]]; do
    echo "Instance still starting... Waiting to associate the Elastic IP..."
    sleep 10
  done
  echo " - Created Instance: ${COLOR_GREEN}${INSTANCE_ID}${COLOR_NC}"
  sleep 10
else
  echo " - Using existing Instance: ${COLOR_GREEN}${INSTANCE_ID}${COLOR_NC}"
fi

## Associate Elastic IP with instance
if [[ "${ELASTIC_IP_ASSOC_ID}" == null ]]; then
  ELASTIC_IP_ASSOC="$(aws_execute -r "ec2 associate-address \
    --allocation-id \"${ELASTIC_IP_ID}\" \
    --instance-id \"${INSTANCE_ID}\"")"
  ELASTIC_IP_ASSOC_ID="$(echo "${ELASTIC_IP_ASSOC}" | jq -r '.AssociationId')"
  echo " - Associated Elastic IP ${ELASTIC_IP_IP} to ${INSTANCE_ID}: ${COLOR_GREEN}${ELASTIC_IP_ASSOC_ID}${COLOR_NC}"
else
  echo " - Elastic IP ${ELASTIC_IP_IP} already associated to ${INSTANCE_ID}: ${COLOR_GREEN}${ELASTIC_IP_ASSOC_ID}${COLOR_NC}"
fi

echo "${COLOR_CYAN}]] Preparing Instance [[${COLOR_NC}"
## SSH in, docker install, and install Build Cloud
  while ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${ELASTIC_IP_IP}" "hostname &>/dev/null" &>/dev/null; do
    echo "Instance ssh still starting..."
    sleep 10
  done
if ! ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${ELASTIC_IP_IP}" "docker-compose --help &>/dev/null"; then
  ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${ELASTIC_IP_IP}" " \
    sudo amazon-linux-extras install -y docker; \
    sudo systemctl enable docker; \
    sudo service docker start; \
    sudo usermod -aG docker ec2-user; \
    sudo yum install -y git jq nc; \
    sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m) -o /usr/local/bin/docker-compose; \
    sudo chmod +x /usr/local/bin/docker-compose;"
  aws_execute -r "ec2 reboot-instances --instance-ids \"${INSTANCE_ID}\""
  echo " ${COLOR_YELLOW}- Instance rebooted${COLOR_NC}"
  sleep 5
  while ! ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${ELASTIC_IP_IP}" "hostname &>/dev/null" &>/dev/null; do
    echo "Instance still booting..."
    sleep 10
  done
fi

if [[ -n "${ANKA_CONTROLLER_IP}" && "${ANKA_CONTROLLER_IP}" != null ]]; then
  echo "${COLOR_CYAN}]] Installing with Docker [[${COLOR_NC}"
  if ! ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${ELASTIC_IP_IP}" "nc -z localhost ${ANKA_CONTROLLER_PORT} &>/dev/null"; then
    ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${ELASTIC_IP_IP}" " \
      git clone https://github.com/veertuinc/getting-started.git; \
      cd getting-started; \
      CLOUD_USE_DOCKERHUB=true CLOUD_CONTROLLER_ADDRESS="${ELASTIC_IP_IP}" CLOUD_REGISTRY_ADDRESS="${ANKA_CONTROLLER_IP}" CLOUD_CONTROLLER_PORT="${CLOUD_CONTROLLER_PORT}" CLOUD_REGISTRY_PORT="${CLOUD_REGISTRY_PORT}" ./ANKA_BUILD_CLOUD/install-anka-build-controller-and-registry-on-docker.bash;
    "
  fi
else
  error "Unable to find Controller instance private IP... Enable to install Anka Build Cloud package..."
fi