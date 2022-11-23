HOST_IP="$(curl -s http://whatismyip.akamai.com/)"
AWS_USE_PROFILE=${AWS_USE_PROFILE:-true}
AWS_CRED_FILE_LOCATION="${AWS_CRED_FILE_LOCATION:-"${HOME}/.aws/credentials"}"
AWS_BUILD_CLOUD_AMI_NAME="${AWS_BUILD_CLOUD_AMI_NAME:-"amzn2-ami-hvm-2.0.20210427.0-x86_64-gp2"}"
AWS_BUILD_CLOUD_MAC_AMI_NAME="${AWS_BUILD_CLOUD_MAC_AMI_NAME:-"anka-build-2.5.7.148-macos-12.4"}"
AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE="${AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE:-""}"
if [[ -z "${AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE}" ]]; then
  AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE="mac1.metal"
fi
if [[ "${AWS_BUILD_CLOUD_MAC_INSTANCE_TYPE}" == "mac2.metal" ]]; then
  AWS_BUILD_CLOUD_MAC_AMI_NAME="${AWS_BUILD_CLOUD_MAC_AMI_NAME:-"anka-build-3.2.0.153-macos-13.0-arm64"}"
fi
AWS_BUILD_CLOUD_INSTANCE_TYPE="${AWS_BUILD_CLOUD_INSTANCE_TYPE:-"t2.small"}"
AWS_BUILD_CLOUD_UNIQUE_LABEL="${AWS_BUILD_CLOUD_UNIQUE_LABEL:-"anka-build-demo-cloud"}"
AWS_ANKA_NODE_UNIQUE_LABEL="${AWS_ANKA_NODE_UNIQUE_LABEL:-"anka-build-demo-node"}"
AWS_NONUNIQUE_LABEL="${AWS_NONUNIQUE_LABEL:-"anka-build-demo"}"
AWS_AUTHORIZE_CIDR="${AWS_AUTHORIZE_CIDR:-"${HOST_IP}/32"}"

aws_execute() {
  VERBOSE=true
  CAPTURE_RETURN=false
  if [ $# -ne 0 ]; then
    unset opt OPTARG OPTIND
    while getopts "sr" opt; do
      case "${opt}" in
        s )
          VERBOSE=false
        ;;
        r )
          CAPTURE_RETURN=true
        ;;
        : ) echo "Invalid Option: -${OPTARG} requires an argument." 1>&2;;
        * ) echo "test" ;;
      esac
    done
  fi
  shift $((OPTIND-1))
  $AWS_USE_PROFILE && [[ -z "${AWS_PROFILE}" ]] && error "Unable to find AWS_PROFILE environment variable... Must be set."
  RETURNED="$(
    eval "$VERBOSE && set -x; aws $*;" || ({ RC=$?; set +x; } 2>/dev/null; echo $RC; )
  )"
  [[ "$RETURNED" =~ ^-?[0-9]+$ ]] && exit $RETURNED
  $CAPTURE_RETURN && echo "${RETURNED}" || true
}

aws_obtain_profile() {
  if [[ ! -z "${AWS_PROFILE}" ]] && [ $(grep -c ^\\[${AWS_PROFILE}\\] $AWS_CRED_FILE_LOCATION) -lt 1 ]; then
    echo "${COLOR_YELLOW}Profile \"${AWS_PROFILE}\" not found...${COLOR_NC}"
    unset AWS_PROFILE
  fi
  if [[ -z "${AWS_PROFILE}" ]]; then
    while true; do
      read -p "Which AWS profile would you like to use? (type the full name from the ~/.aws/credentials file): " AWS_PROFILE
      case "${AWS_PROFILE}" in
        "" ) echo "${COLOR_RED}Please type the name of the profile to use...${COLOR_NC}";;
        * ) 
          if [ $(grep -c ^\[${AWS_PROFILE}\] $AWS_CRED_FILE_LOCATION) -lt 1 ]; then
            echo "${COLOR_YELLOW}Profile \"${AWS_PROFILE}\" not found...${COLOR_NC}"
          else
            break
          fi
        ;;
      esac
      echo ""
    done
  fi
  echo "] AWS Profile: ${COLOR_GREEN}${AWS_PROFILE}${COLOR_NC}";
}

aws_obtain_region() {
  if [[ -z "${AWS_REGION}" ]]; then
    while true; do
      read -p "Which AWS region would you like to use?: " AWS_REGION
      case "${AWS_REGION}" in
        "" ) echo "${COLOR_YELLOW}Please type the name of the region to use...${COLOR_NC}";;
        * ) break;;
      esac
      echo ""
    done
  fi
  echo "] AWS Region: ${COLOR_GREEN}${AWS_REGION}${COLOR_NC}";
}

aws_obtain_key_pair() {
  if [[ -z "${AWS_KEY_PAIR_NAME}" ]]; then
    while true; do
      read -p "Which AWS key pair would you like to use when creating the instance?: " AWS_KEY_PAIR_NAME
      case "${AWS_KEY_PAIR_NAME}" in
        "" ) echo "${COLOR_YELLOW}Please type the name of the key pair to use...${COLOR_NC}";;
        * ) break;;
      esac
      echo ""
    done
  fi
  AWS_KEY_PATH="${AWS_KEY_PATH:-"${HOME}/.ssh/${AWS_KEY_PAIR_NAME}.pem"}"
  if [[ ! -e "${AWS_KEY_PATH}" ]]; then
    error "Unable to find ${AWS_KEY_PATH} (You can change the location of the ssh key by setting the AWS_KEY_PATH env variable)"
    exit 10
  fi 
  echo "] AWS Key Pair: ${COLOR_GREEN}${AWS_KEY_PAIR_NAME}${COLOR_NC}";
}