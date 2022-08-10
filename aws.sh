function aws-assume() {
  aws sts get-caller-identity ${@:2}
  EXIT_CODE=$?

  if [[ "$EXIT_CODE" != 0 ]]; then
    aws sso login ${@:2}
    aws sts get-caller-identity ${@:2}
  fi


  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
  role=$1
  output=$(aws sts assume-role --role-arn $role --role-session-name AWSCLI ${@:2}| yq -P e)
  export AWS_ACCESS_KEY_ID=$(echo $output | yq -P e ".Credentials.AccessKeyId" -)
  export AWS_SECRET_ACCESS_KEY=$(echo $output | yq -P e ".Credentials.SecretAccessKey" -)
  export AWS_SESSION_TOKEN=$(echo $output | yq -P e ".Credentials.SessionToken" -)

  aws sts get-caller-identity
}

function aws-sso() {
  aws sts get-caller-identity --profile $1
  EXIT_CODE=$?

  if [[ "$EXIT_CODE" != 0 ]]; then
    aws sso login --profile $1
    aws sts get-caller-identity
  fi
}

function aws-switch() {
  aws-sso $1
  export AWS_PROFILE=$1
}

function aws-kube-config() {
  profile=${AWS_PROFILE:-default}
  region=""
  role_filter="system-master"
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --profile)
        profile=$2
        shift
        ;;
      --region)
        region=$2
        shift
        ;;
      --name)
        clusters=$2
        shift
        ;;
      --role)
        role=$2
        shift
        ;;
      --role-arn)
        role_arn=$2
        shift
        ;;
      --alias)
        alias=$2
        shift
        ;;
      --role-filter)
        role_filter=$2
        shift
        ;;
     *)
       shift
       ;;
    esac
  done
  
  if [[ -z $region ]]; then
    region=$(aws configure get region --profile $profile)
  fi
  
  if [[ -z $clusters ]]; then
    clusters=$(aws eks list-clusters --output json --profile $profile | jq -cr ".clusters[]")
  fi

  if [[ -z $role_arn  ]]; then
    if [[ -n $role ]]; then
      account=$(aws sts get-caller-identity --output json --profile $profile | jq -r ".Account")
      role_arn="arn:aws:iam:$account:role/$role"
    fi
  fi
  
  for c in $clusters; do
    if [[ -z $role_arn ]]; then
      role_arn=$(aws iam list-roles --query 'Roles[*].Arn' --output json --profile $profile| jq -rc ".[]" | grep $c | grep $role_filter)
    fi

    if [[ ! $clusters = *" "* ]] && [[ -z $alias ]]; then
      alias="$c-$role_filter"
    fi
    _cmd="aws eks update-kubeconfig --region $region --name $c --role-arn $role_arn --profile $profile --alias $alias"
    echo $_cmd
    eval $_cmd
  done
  
}

function _profile_completion() {
  reply=$(cat ~/.aws/config | grep profile | sed -E 's/.*profile.([a-z_]+).*/\1/g')
  COMPREPLY=($(compgen -W "$reply"))
  return 0
}

complete -F _profile_completion aws-sso aws-switch