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

  if [[ "${INSTANCE_ID}" != null ]]; then
    aws_execute "ec2 terminate-instances --instance-ids \"${INSTANCE_ID}\""
    while [[ "$(aws_execute -r -s "ec2 describe-instances --instance-ids \"${INSTANCE_ID}\"" | jq -r '.Reservations[0].Instances[0].State.Name')" != 'terminated' ]]; do
      echo "Instance terminating..."
      sleep 50
    done
    aws_execute "ec2 delete-tags --resources \"${INSTANCE_ID}\" --tags Key=purpose Key=Name"
  fi

  if [[ "${DEDICATED_HOST_ID}" != null ]]; then
    if [[ "${DEDICATED_HOST_STATE}" == "released" ]]; then
      aws_execute "ec2 delete-tags --resources \"${DEDICATED_HOST_ID}\" --tags Key=purpose Key=Name"
    fi
  fi

  warning "Dedicated Hosts are unable to be programmatically released in a Pending state.
         Due to the amount of time required to transition macOS hosts from Pending to Available, you'll need to release the dedicated host manually in the AWS console."
  # [[ "${DEDICATED_HOST_ID}" != null ]] && aws_execute "ec2 release-hosts --host-ids \"${DEDICATED_HOST_ID}\""

}
if [[ "$1" != "--delete" ]]; then
  echo "${COLOR_CYAN}========================================${COLOR_NC}"
  echo "${COLOR_CYAN}]] Creating and setting up Anka Nodes [[${COLOR_NC}"
fi
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
# if [[ "$1" != "--delete" ]]; then
aws_obtain_key_pair
echo "] AWS User: ${COLOR_GREEN}$(aws_execute -s -r "iam get-user | jq -r '.User.UserName, \"|\", .User.UserId' | xargs")${COLOR_NC}";
# fi
echo "${COLOR_CYAN}========================================${COLOR_NC}"

# Collect all existing ids and instances
DEDICATED_HOST="$(aws_execute -r -s "ec2 describe-hosts --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"")"
DEDICATED_HOST_ID="$(echo "${DEDICATED_HOST}" | jq -r '.Hosts[0].HostId')"
DEDICATED_HOST_STATE="$(echo "${DEDICATED_HOST}" | jq -r '.Hosts[0].State')"
SECURITY_GROUP="$(aws_execute -r -s "ec2 describe-security-groups --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"")"
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-"$(echo "${SECURITY_GROUP}" | jq -r '.SecurityGroups[0].GroupId')"}"

if [[ "$1" != "--delete" ]] && ${CONTROLLER_ENABLED:-true}; then
  obtain_anka_license
  [[ "${SECURITY_GROUP_ID}" == null ]] && error "Unable to find Security Group... Please run the prepare-build-cloud.bash script first OR set SECURITY_GROUP_ID before execution..."
  CONTROLLER_ADDRESSES="$(aws_execute -r -s "ec2 describe-addresses --filter \"Name=tag:purpose,Values=${AWS_BUILD_CLOUD_UNIQUE_LABEL}\"")"
  ANKA_CONTROLLER_PRIVATE_IP="${ANKA_CONTROLLER_PRIVATE_IP:-"$(echo "${CONTROLLER_ADDRESSES}" | jq -r '.Addresses[0].PrivateIpAddress')"}"
  if [[ "${ANKA_CONTROLLER_PRIVATE_IP}" == null ]]; then error "Unable to find Private IP for Controller... Please run the prepare-build-cloud.bash script first OR set ANKA_CONTROLLER_PRIVATE_IP before execution..."; fi
  CLI_OPTIONS="--user-data \"export ANKA_CONTROLLER_ADDRESS=\\\"http://${ANKA_CONTROLLER_PRIVATE_IP}:${CLOUD_CONTROLLER_PORT}\\\" export ANKA_LICENSE=\\\"${ANKA_LICENSE}\\\" export ANKA_PULL_LATEST_CLOUD_CONNECT=true export ANKA_PRE_WARM_ROOT_VOL=true export ANKA_USE_PUBLIC_IP=true\""
fi
INSTANCE="$(aws_execute -r -s "ec2 describe-instances --filters \"Name=instance-state-name,Values=running\" \"Name=tag:purpose,Values=${AWS_ANKA_NODE_UNIQUE_LABEL_PURPOSE}\"")"
INSTANCE_ID="$(echo "${INSTANCE}" | jq -r '.Reservations[0].Instances[0].InstanceId')"
if [[ "${INSTANCE_ID}" != 'null' ]]; then INSTANCE_IP="$(aws_execute -r -s "ec2 describe-instances --instance-ids \"${INSTANCE_ID}\" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text")"; fi

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
  echo " - Using existing Security Group: ${COLOR_GREEN}${SECURITY_GROUP_ID} | ${AWS_BUILD_CLOUD_UNIQUE_LABEL}${COLOR_NC}"
fi

# Add IP to security group
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr ${AWS_AUTHORIZE_CIDR} &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 5900-5920 --cidr ${AWS_AUTHORIZE_CIDR} &>/dev/null || true"
aws_execute -s "ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 8099-50000 --source-group $SECURITY_GROUP_ID &>/dev/null || true" # added 8099 for support with Jenkins in AMI creation pipeline / 50000 for JNLP and Jenkins

echo " - Added ${HOST_IP} to Security Group ${SECURITY_GROUP_ID}"

# Create dedicated for macOS metal instances
if [[ "${DEDICATED_HOST_ID}" == null ]]; then
  outer_loop_broken=false
  for i in {1..20}; do
    for AVAILABILITY_ZONE in $(aws ec2 describe-instance-type-offerings --filters Name=instance-type,Values=${AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE} --location-type availability-zone --region ${AWS_REGION} --query "InstanceTypeOfferings[].Location" --output text); do
      echo "${AVAILABILITY_ZONE}"
      if ! DEDICATED_HOST=$(aws_execute -r "ec2 allocate-hosts \
        --quantity 1 \
        --availability-zone \"${AVAILABILITY_ZONE}\" \
        --instance-type \"${AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE}\" \
        --tag-specifications \"ResourceType=dedicated-host,Tags=[{Key=Name,Value="${AWS_NONUNIQUE_LABEL} Anka Node"},{Key=purpose,Value=${AWS_NONUNIQUE_LABEL}}]\""); then
        continue
      else
        outer_loop_broken=true
        break
      fi
    done
    if [[ "$outer_loop_broken" = true ]]; then
      break
    fi
    echo "Attempt $i failed, retrying in 120 seconds..."
    sleep 120
  done
  DEDICATED_HOST_ID="$(echo "${DEDICATED_HOST}" | jq -r '.HostIds[0]')"
  [[ -n "${DEDICATED_HOST}" && "${DEDICATED_HOST}" != 'null' ]] || (echo "unable to create dedicated host right now.. try again later" && exit 2)
  echo " - Requested Dedicated Host: ${COLOR_GREEN}${DEDICATED_HOST_ID}${COLOR_NC}"
else
  echo " - Using Dedicated Host: ${COLOR_GREEN}${DEDICATED_HOST_ID}${COLOR_NC}"
fi

# Create EC2 instance for Anka Node
if [[ "${INSTANCE_ID}" == null ]]; then
  while [[ "$(aws_execute -r -s "ec2 describe-hosts --filter \"Name=tag:purpose,Values=${AWS_NONUNIQUE_LABEL}\"" | jq -r '.Hosts[0].State')" != 'available' ]]; do
    echo "Dedicated Host still not available (this can take a while)..."
    sleep 60
  done
  # Fix An error occurred (InvalidHostState) when calling the RunInstances operation: Dedicated host h-XXX is in an invalid state for launching instances.
  sleep 120
  while [[ "$(aws_execute -r -s "ec2 describe-hosts --host-ids \"${DEDICATED_HOST_ID}\"" | jq -r '.Hosts[0].AvailableCapacity.AvailableInstanceCapacity[0].AvailableCapacity')" != "1" ]]; do
    echo "Dedicated Host capacity still not available (this can take a while)..."
    sleep 60
  done
  ## Get latest AMI ID (regardless of region)
  echo "${COLOR_CYAN}]] Creating Instance${COLOR_NC}"
  COMMUNITY_AMI_ID="${COMMUNITY_AMI_ID:-$(aws_execute -r -s "ec2 describe-images \
    --filters \"Name=name,Values=anka-build-*\" \"Name=state,Values=available\" \"Name=owner-id,Values=930457884660\" \
    --query \"Images[?contains(Name,\\\`marketplace\\\`) == \\\`false\\\`] ${EXTRA_CONTAINS} | sort_by([*], &CreationDate)[-1].[ImageId]\" \
    --output \"text\"")}"
  # We don't use ANKA_JOIN_ARGS here so we can set the instance IP
  AWS_ANKA_NODE_NAME_TAG_LABEL="${AWS_ANKA_NODE_NAME_TAG_LABEL:-"Anka Build Node"}"
  INSTANCE=$(aws_execute -r "ec2 run-instances \
    --image-id \"${COMMUNITY_AMI_ID}\" \
    --instance-type=\"${AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE}\" \
    --security-group-ids \"${SECURITY_GROUP_ID}\" \
    --placement \"HostId=${DEDICATED_HOST_ID}\" \
    --key-name \"${AWS_KEY_PAIR_NAME}\" \
    --count 1 \
    --associate-public-ip-address \
    --ebs-optimized \
    --block-device-mappings \"[\$(aws ec2 describe-images --image-ids $COMMUNITY_AMI_ID --query \"Images[0].BlockDeviceMappings[0]\" --output json | jq -cr '.Ebs.VolumeType = \"gp3\" | .Ebs.VolumeSize = ${EBS_VOLUME_SIZE:-200} | .Ebs.Iops = 6000 | .Ebs.Throughput = 256')]\" \
    --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value="${AWS_ANKA_NODE_UNIQUE_LABEL} ${AWS_ANKA_NODE_NAME_TAG_LABEL}"},{Key=purpose,Value="${AWS_ANKA_NODE_UNIQUE_LABEL_PURPOSE}"}]\" ${CLI_OPTIONS}")
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
if [[ -n "${INSTANCE_IP}" && "${INSTANCE_IP}" != null ]]; then
  while ! ssh -o "StrictHostKeyChecking=no" -o "ConnectTimeout=1" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "hostname &>/dev/null" &>/dev/null; do
    echo "Instance still starting..."
    sleep 60
  done
  # if ${PREP:-true}; then
  #   echo "${COLOR_CYAN}]] Preparing Instance${COLOR_NC}"
  #   echo "Prewarming the EBS volume for maximum performance"
  #   ssh -o "StrictHostKeyChecking=no" -i "${AWS_KEY_PATH}" "ec2-user@${INSTANCE_IP}" "PATH=\"/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:\$PATH\" brew install fio; sudo fio --filename=/dev/r\$(df -h / | grep -o 'disk[0-9]') --rw=read --bs=1M --iodepth=32 --ioengine=posixaio --direct=1 --name=volume-initialize"
  # fi
else
  echo "Instance failed to be created"
  exit 1
fi

echo "You can now access your Anka Node with:"
echo "${COLOR_GREEN}   ssh -i \"${AWS_KEY_PATH}\" \"ec2-user@${INSTANCE_IP}\"${COLOR_NC}"
echo ""