#!/bin/bash
set -eo pipefail
AWS_PAGER=
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"
. ../shared.bash
[[ -z $(command -v jq) ]] && error "JQ is required. You can install it with brew install jq."
warning "This script is tested with AWS CLI v2.2.9. If your version differs (mostly a concern for older versions), there is no guarantee it will function as expected!${COLOR_NC}" && sleep 2
cleanup() {

  [[ -n "${INSTANCE_IP}" && "${INSTANCE_IP}" != null ]] && ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" " \
    export PATH=\"/usr/local/bin:\$PATH\"; \
    echo y | sudo anka license remove || true;\
    sudo ankacluster disjoin || true; \
  " && warning "Save the fulfillment ID above and send it to support@veertu.com to release the cores"

  [[ "${INSTANCE_ID}" != null ]] && aws_execute "ec2 terminate-instances \
  --instance-ids \"${INSTANCE_ID}\""

  warning "Dedicated Hosts are unable to be programmatically released in a Pending state.
         Due to the amount of time required to transition macOS hosts from Pending to Available, you'll need to release the dedicated host manually in the AWS console."
  # [[ "${DEDICATED_HOST_ID}" != null ]] && aws_execute "ec2 release-hosts --host-ids \"${DEDICATED_HOST_ID}\""

}

echo "${COLOR_CYAN}========================================${COLOR_NC}"
echo "${COLOR_CYAN}]] Creating and setting up Anka Nodes [[${COLOR_NC}"
echo "${COLOR_CYAN}========================================${COLOR_NC}"

[[ "$(uname)" != "Darwin" ]] && echo "${COLOR_YELLOW}WARNING: We cannot guarantee this script with function on modern non-Darwin/MacOS shells (bash or zsh)${COLOR_NC}" && sleep 2
# Ensure aws cli is installed
[[ -z "$(command -v aws)" ]] && error "aws command not found; https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html${COLOR_NC}"
[[ ! -e "${AWS_CRED_FILE_LOCATION}" ]] && error "No credentials file found in ${AWS_CRED_FILE_LOCATION}..."
# Ensure --profile is set for cli
aws_obtain_profile
# Ensure region is set for cli
aws_obtain_region
# Ensure the key pair for instance creation is set
aws_obtain_key_pair
echo "] AWS User: ${COLOR_GREEN}$(aws_execute -s -r "iam get-user | jq -r '.User.UserName, \"|\", .User.UserId' | xargs")${COLOR_NC}";
echo "${COLOR_CYAN}========================================${COLOR_NC}"

# Collect all existing ids and instances
DEDICATED_HOST="$(aws_execute -r -s "ec2 describe-hosts --filter \"Name=tag:purpose,Values=${AWS_SECURITY_GROUP_NAME}\"")"
DEDICATED_HOST_ID="$(echo "${DEDICATED_HOST}" | jq -r '.Hosts[0].HostId')"
SECURITY_GROUP="$(aws_execute -r -s "ec2 describe-security-groups --filter \"Name=tag:purpose,Values=${AWS_SECURITY_GROUP_NAME}\"")"
SECURITY_GROUP_ID="$(echo "${SECURITY_GROUP}" | jq -r '.SecurityGroups[0].GroupId')"
[[ "${SECURITY_GROUP_ID}" == null ]] && error "Unable to find Security Group... Please run the prepare-build-cloud.bash script first..."
CONTROLLER_ADDRESSES="$(aws_execute -r -s "ec2 describe-addresses --filter \"Name=tag:purpose,Values=${AWS_SECURITY_GROUP_NAME}\"")"
CONTROLLER_PRIV_IP="$(echo "${CONTROLLER_ADDRESSES}" | jq -r '.Addresses[0].PrivateIpAddress')"
[[ "${CONTROLLER_PRIV_IP}" == null ]] && error "Unable to find Private IP for Controller... Please run the prepare-build-cloud.bash script first..."
INSTANCE="$(aws_execute -r -s "ec2 describe-instances --filters \"Name=host-id,Values=${DEDICATED_HOST_ID}\" \"Name=instance-state-name,Values=running\" \"Name=tag:purpose,Values=${AWS_SECURITY_GROUP_NAME}\"")"
INSTANCE_ID="$(echo "${INSTANCE}" | jq -r '.Reservations[0].Instances[0].InstanceId')"
[[ "${INSTANCE_ID}" != null ]] && INSTANCE_IP="$(aws_execute -r -s "ec2 describe-instances --instance-ids \"${INSTANCE_ID}\" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text")"

# Cleanup
if [[ "$1" == "--delete" ]]; then
  cleanup
  exit
fi

# Create dedicated for macOS metal instances
if [[ "${DEDICATED_HOST_ID}" == null ]]; then
  AVAILABILITY_ZONES="$(aws_execute -r "ec2 describe-availability-zones --all-availability-zones" | jq -r '.AvailabilityZones')"
  AVAILABILITY_ZONE="$(echo ${AVAILABILITY_ZONES} | jq -r '.[0].ZoneName')"
  while ! DEDICATED_HOST=$(aws_execute -r "ec2 allocate-hosts \
    --quantity 1 \
    --availability-zone \"${AVAILABILITY_ZONE}\" \
    --instance-type \"mac1.metal\" \
    --tag-specifications \"ResourceType=dedicated-host,Tags=[{Key=Name,Value="Anka Build Cloud"},{Key=purpose,Value=${AWS_SECURITY_GROUP_NAME}}]\""); do
    read -p "Which ${AWS_REGION} AZ would you like to try instead?: " AVAILABILITY_ZONE
    case "${AVAILABILITY_ZONE}" in
      "" ) echo "${COLOR_RED}Please type the name of the AZ to use...${COLOR_NC}";;
      * ) ;;
    esac
    echo ""
  done
  DEDICATED_HOST_ID="$(echo "${DEDICATED_HOST}" | jq -r '.HostIds[0]')"
  echo " - Requested Dedicated Host: ${COLOR_GREEN}${DEDICATED_HOST_ID}${COLOR_NC}"
else
  echo " - Using Dedicated Host: ${COLOR_GREEN}${DEDICATED_HOST_ID}${COLOR_NC}"
fi

# Create EC2 mac1.metal instance for Anka Node
if [[ "${INSTANCE_ID}" == null ]]; then
  while [[ "$(aws_execute -r -s "ec2 describe-hosts --filter \"Name=tag:purpose,Values=${AWS_SECURITY_GROUP_NAME}\"" | jq -r '.Hosts[0].State')" != 'available' ]]; do
    echo "Dedicated Host still not available (this can take a while)..."
    sleep 60
  done
  while [[ "$(aws_execute -r -s "ec2 describe-hosts --host-ids \"${DEDICATED_HOST_ID}\"" | jq -r '.Hosts[0].AvailableCapacity.AvailableInstanceCapacity[0].AvailableCapacity')" != "1" ]]; do
    echo "Dedicated Host capacity still not available (this can take a while)..."
    sleep 60
  done
  ## Get latest AMI ID (regardless of region)
  echo "${COLOR_CYAN}]] Creating Instance${COLOR_NC}"
  AMI_ID="$(aws_execute -r -s "ec2 describe-images \
    --owners \"amazon\" \
    --filters \"Name=name,Values=${AWS_BUILD_CLOUD_MAC_AMI_NAME}\" \"Name=state,Values=available\" \
    --query \"sort_by(Images, &CreationDate)[-1].[ImageId]\" \
    --output \"text\"")"
  INSTANCE=$(aws_execute -r "ec2 run-instances \
    --image-id \"${AMI_ID}\" \
    --instance-type=\"mac1.metal\" \
    --security-group-ids \"${SECURITY_GROUP_ID}\" \
    --placement \"HostId=${DEDICATED_HOST_ID}\" \
    --key-name \"${AWS_KEY_PAIR_NAME}\" \
    --count 1 \
    --associate-public-ip-address \
    --ebs-optimized \
    --user-data \"export ANKA_CONTROLLER_ADDRESS=\\\"http://${CONTROLLER_PRIV_IP}\\\"\" \
    --block-device-mappings \"DeviceName=/dev/sda1,Ebs={VolumeSize=400,VolumeType=gp3}\" \
    --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value="Anka Build Cloud Controller and Registry"},{Key=purpose,Value=${AWS_SECURITY_GROUP_NAME}}]\"")
  INSTANCE_ID="$(echo "${INSTANCE}" | jq -r '.Instances[0].InstanceId')"
  while [[ "$(aws_execute -r -s "ec2 describe-instance-status --instance-ids \"${INSTANCE_ID}\"" | jq -r '.InstanceStatuses[0].InstanceState.Name')" != 'running' ]]; do
    echo "Instance still starting..."
    sleep 10
  done
  INSTANCE_IP="$(aws_execute -r -s "ec2 describe-instances \
    --instance-ids \"${INSTANCE_ID}\" \
    --query 'Reservations[*].Instances[*].PublicIpAddress' --output text")"
  echo " - Created Instance: ${COLOR_GREEN}${INSTANCE_ID} | ${INSTANCE_IP}${COLOR_NC}"
  sleep 10
else
  echo " - Using existing Instance: ${COLOR_GREEN}${INSTANCE_ID} | ${INSTANCE_IP}${COLOR_NC}"
fi

### Use AMI repo to install everything we need into the metal instance
if [[ "${INSTANCE_IP}" != null ]]; then
  while ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "hostname &>/dev/null" &>/dev/null; do
    echo "Instance still starting..."
    sleep 60
  done
  ## SSH in, docker install, and install Build Cloud
  if ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "PATH=\"/usr/local/bin:\$PATH\" anka version &>/dev/null"; then
    echo "${COLOR_CYAN}]] Preparing Instance${COLOR_NC}"
    obtain_anka_license
    ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" " \
      cd /Users/ec2-user && rm -rf aws-ec2-mac-amis && git clone https://github.com/veertuinc/aws-ec2-mac-amis.git && cd aws-ec2-mac-amis && ANKA_JOIN_ARGS=\"--host ${INSTANCE_IP} --name node1-${AWS_REGION}\" ANKA_LICENSE=\"${ANKA_LICENSE}\" ./\$(sw_vers | grep ProductVersion | cut -d: -f2 | xargs)/prepare.bash; \
    "
    aws_execute -r "ec2 reboot-instances --instance-ids \"${INSTANCE_ID}\""
    echo " ${COLOR_YELLOW}- Instance rebooted (it will join to the controller on boot)${COLOR_NC}"
    sleep 40
    while [[ "$(aws_execute -r -s "ec2 describe-instance-status --instance-ids \"${INSTANCE_ID}\"" | jq -r '.InstanceStatuses[0].SystemStatus.Status')" != 'ok' ]]; do
      echo "Instance still starting..."
      sleep 10
    done
  else
    echo " - Anka already installed in instance"
  fi
fi

while ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "hostname &>/dev/null" &>/dev/null; do
  echo "Instance still booting..."
  sleep 10
done

echo "${COLOR_CYAN}==============================================${COLOR_NC}"

echo "You can now access your Anka Node with:"
echo "${COLOR_GREEN}   ssh -i \"${AWS_KEY_PATH}\" \"ec2-user@${INSTANCE_IP}\"${COLOR_NC}"