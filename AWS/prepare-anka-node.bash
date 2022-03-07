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

  [[ -n "${INSTANCE_IP}" && "${INSTANCE_IP}" != null ]] && ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" " \
    export PATH=\"/usr/local/bin:\$PATH\"; \
    echo y | sudo anka license remove 2>/dev/null || true;\
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
echo "${COLOR_CYAN}========================================${COLOR_NC}"

# Collect all existing ids and instances
DEDICATED_HOST="$(aws_execute -r -s "ec2 describe-hosts --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"")"
DEDICATED_HOST_ID="$(echo "${DEDICATED_HOST}" | jq -r '.Hosts[0].HostId')"
SECURITY_GROUP="$(aws_execute -r -s "ec2 describe-security-groups --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"")"
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-"$(echo "${SECURITY_GROUP}" | jq -r '.SecurityGroups[0].GroupId')"}"
[[ "${SECURITY_GROUP_ID}" == null ]] && error "Unable to find Security Group... Please run the prepare-build-cloud.bash script first OR set SECURITY_GROUP_ID before execution..."
CONTROLLER_ADDRESSES="$(aws_execute -r -s "ec2 describe-addresses --filter \"Name=tag:purpose,Values=${AWS_BUILD_CLOUD_UNIQUE_LABEL}\"")"
ANKA_CONTROLLER_PRIVATE_IP="${ANKA_CONTROLLER_PRIVATE_IP:-"$(echo "${CONTROLLER_ADDRESSES}" | jq -r '.Addresses[0].PrivateIpAddress')"}"
[[ "${ANKA_CONTROLLER_PRIVATE_IP}" == null ]] && error "Unable to find Private IP for Controller... Please run the prepare-build-cloud.bash script first OR set ANKA_CONTROLLER_PRIVATE_IP before execution..."
INSTANCE="$(aws_execute -r -s "ec2 describe-instances --filters \"Name=host-id,Values=${DEDICATED_HOST_ID}\" \"Name=instance-state-name,Values=running\" \"Name=tag:purpose,Values=${AWS_ANKA_NODE_UNIQUE_LABEL}\"")"
INSTANCE_ID="$(echo "${INSTANCE}" | jq -r '.Reservations[0].Instances[0].InstanceId')"
[[ "${INSTANCE_ID}" != null ]] && INSTANCE_IP="$(aws_execute -r -s "ec2 describe-instances --instance-ids \"${INSTANCE_ID}\" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text")"

# Cleanup
if [[ "$1" == "--delete" ]]; then
  cleanup
  exit
fi

obtain_anka_license

# Add IP to security group
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr ${AWS_AUTHORIZE_CIDR} &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 5900-5920 --cidr ${AWS_AUTHORIZE_CIDR} &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 10000-10010 --source-group $SECURITY_GROUP_ID &>/dev/null || true"
echo " - Added ${HOST_IP} to Security Group ${SECURITY_GROUP_ID} (22, 5900-5920, 10000-10010)"

# Create dedicated for macOS metal instances
if [[ "${DEDICATED_HOST_ID}" == null ]]; then
  AVAILABILITY_ZONES="$(aws_execute -r "ec2 describe-availability-zones --all-availability-zones" | jq -r '.AvailabilityZones')"
  AVAILABILITY_ZONE="$(echo ${AVAILABILITY_ZONES} | jq -r '.[0].ZoneName')"
  while ! DEDICATED_HOST=$(aws_execute -r "ec2 allocate-hosts \
    --quantity 1 \
    --availability-zone \"${AVAILABILITY_ZONE}\" \
    --instance-type \"mac1.metal\" \
    --tag-specifications \"ResourceType=dedicated-host,Tags=[{Key=Name,Value="${AWS_NONUNIQUE_LABEL} Anka Node"},{Key=purpose,Value=${AWS_NONUNIQUE_LABEL}}]\""); do
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
  while [[ "$(aws_execute -r -s "ec2 describe-hosts --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"" | jq -r '.Hosts[0].State')" != 'available' ]]; do
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
    --filters \"Name=name,Values=${AWS_BUILD_CLOUD_MAC_AMI_NAME}\" \"Name=state,Values=available\" \
    --query \"sort_by(Images, &CreationDate)[-1].[ImageId]\" \
    --output \"text\"")"
  # We don't use ANKA_JOIN_ARGS here so we can set the instance IP
  INSTANCE=$(aws_execute -r "ec2 run-instances \
    --image-id \"${AMI_ID}\" \
    --instance-type=\"mac1.metal\" \
    --security-group-ids \"${SECURITY_GROUP_ID}\" \
    --placement \"HostId=${DEDICATED_HOST_ID}\" \
    --key-name \"${AWS_KEY_PAIR_NAME}\" \
    --count 1 \
    --associate-public-ip-address \
    --ebs-optimized \
    --user-data \"export ANKA_CONTROLLER_ADDRESS=\\\"http://${ANKA_CONTROLLER_PRIVATE_IP}:${CLOUD_CONTROLLER_PORT}\\\" export ANKA_LICENSE=\\\"${ANKA_LICENSE}\\\" export ANKA_USE_PUBLIC_IP=true\" \
    --block-device-mappings '[{ \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 500, \"VolumeType\": \"gp3\", \"Iops\": 6000, \"Throughput\": 256 }}]' \
    --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value="${AWS_ANKA_NODE_UNIQUE_LABEL} Anka Build Node"},{Key=purpose,Value=${AWS_ANKA_NODE_UNIQUE_LABEL}}]\"")
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
# Disabled now that our AMI exists
# if [[ "${INSTANCE_IP}" != null ]]; then
#   while ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "hostname &>/dev/null" &>/dev/null; do
#     echo "Instance still starting..."
#     sleep 60
#   done
#   #### SSH in, docker install, and install Build Cloud
#   if ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "PATH=\"/usr/local/bin:\$PATH\" anka version &>/dev/null"; then
#     echo "${COLOR_CYAN}]] Preparing Instance${COLOR_NC}"
#     obtain_anka_license
#     ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" " \
#       cd /Users/ec2-user && rm -rf aws-ec2-mac-amis && git clone https://github.com/veertuinc/aws-ec2-mac-amis.git && \
#       cd aws-ec2-mac-amis && ANKA_JOIN_ARGS=\"--host ${INSTANCE_IP} --name node1-${AWS_REGION}\" ANKA_LICENSE=\"${ANKA_LICENSE}\" ./\$(sw_vers | grep ProductVersion | cut -d: -f2 | xargs)/prepare.bash; \
#     "
#     while ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "grep \"Finished APFS operation\" /var/log/resize-disk.log &>/dev/null" &>/dev/null; do
#       echo "Waiting for APFS resize to finish..."
#       sleep 10
#     done
#     sleep 2
#     aws_execute -r "ec2 reboot-instances --instance-ids \"${INSTANCE_ID}\""
#     echo " ${COLOR_YELLOW}- Instance rebooted (it will join to the controller on boot)${COLOR_NC}"
#     sleep 40
#     while [[ "$(aws_execute -r -s "ec2 describe-instance-status --instance-ids \"${INSTANCE_ID}\"" | jq -r '.InstanceStatuses[0].SystemStatus.Status')" != 'ok' ]]; do
#       echo "Instance still starting..."
#       sleep 10
#     done
#   else
#     echo " - Anka already installed in instance"
#   fi
# fi

#### SSH in and prepare the machine so it has the public IP
if [[ "${INSTANCE_IP}" != null ]]; then
  while ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "hostname &>/dev/null" &>/dev/null; do
    echo "Instance still starting..."
    sleep 60
  done
  if ${PREP:-true}; then
    echo "${COLOR_CYAN}]] Preparing Instance${COLOR_NC}"
    ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" " \
      sudo launchctl unload -w /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist; \
      sudo pkill timed && date && \
      sudo /usr/libexec/PlistBuddy -c 'Delete :ProgramArguments:2' /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist || true && \
      sudo /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:2 string "--host ${INSTANCE_IP} --reserve-space 20GB --node-id ${INSTANCE_ID}"' /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist && \
      sudo launchctl load -w /Library/LaunchDaemons/com.veertu.aws-ec2-mac-amis.cloud-connect.plist && \
      sleep 30 && tail -50 /var/log/cloud-connect.log \
    "
  fi
fi

echo "You can now access your Anka Node with:"
echo "${COLOR_GREEN}   ssh -i \"${AWS_KEY_PATH}\" \"ec2-user@${INSTANCE_IP}\"${COLOR_NC}"
echo ""
echo "IMPORTANT: Our AMIs attempt to do the majority of preparation for you, however, there are several steps you need to perform once the instance is started:"
echo "Set password with sudo /usr/bin/dscl . -passwd /Users/ec2-user {NEWPASSWORDHERE} zbun0ok="
echo "You now need to VNC in and log into the ec2-user (requirement for Anka to start the hypervisor): open vnc://ec2-user:{GENERATEDPASSWORD}@{INSTANCEPUBLICIP}"
echo ""
echo "You will find a getting-started directory under the user's home folder which contains a script to help you generate your first Anka VM Template and Tags."