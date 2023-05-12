_vault_common_commands="read write delete list login status unwrap"

CFVAULT_ALIASES_PATH=${CFVAULT_ALIASES_PATH:-"$HOME/.vault_aliases"}
CFVAULT_ACCESS_PATH=${CFVAULT_ACCESS_PATH:-"$HOME/.vault_access"}
CFVAULT_ALIAS_FILE_PATH=${CFVAULT_ALIAS_FILE_PATH:-"$HOME/.vault_alias"}

if [[ ! -d ${CFVAULT_ALIASES_PATH} ]]; then
  echo "vault aliases directory does not exist [${CFVAULT_ALIASES_PATH}]. This will be used to map vault names to a vault URL. "
  echo "Format: ${CFVAULT_ALIASES_PATH}/<alias>"
  echo "Alias content: url of the vault"
  echo "Creating the directory: ${CFVAULT_ALIASES_PATH}"
  mkdir -p ${CFVAULT_ALIASES_PATH}
fi

if [[ ! -d ${CFVAULT_ACCESS_PATH} ]]; then
  echo "vault access directory does not exist [${CFVAULT_ACCESS_PATH}]. This will be used to store credentials for a given vault instance"
  echo "Creating the directory: ${CFVAULT_ACCESS_PATH}"
  mkdir -p ${CFVAULT_ACCESS_PATH}
fi

function _vault_login() {
  if [[ $VAULT_METHOD == "oidc" ]] && [[ ! -f ${CFVAULT_ACCESS_PATH}/$VAULT_ALIAS/vault_token ]]; then
    vault login -address="$addr" -header="cf-access-token=$(cat ${CFVAULT_ACCESS_PATH}/$VAULT_ALIAS/cf_token)" -token-only -method=oidc role="$VAULT_ROLE" > ${CFVAULT_ACCESS_PATH}/$VAULT_ALIAS/vault_token
  else
    echo "existing vault token found for $VAULT_ALIAS. Will use the vault token."
  fi
}

function _vault_get_opts_alias() {
  echo "${VAULT_ALIAS:-$([[ -f ${CFVAULT_ALIAS_FILE_PATH} ]] && cat ${CFVAULT_ALIAS_FILE_PATH})}"
}

function _vault_get_opts_token() {
  echo "${VAULT_TOKEN:-$(cat ${CFVAULT_ACCESS_PATH}/$(_vault_get_opts_alias)/vault_token)}"
}

function _vault_get_opts_address() {
  echo "${VAULT_ADDR:-$(cat ${CFVAULT_ALIASES_PATH}/$(_vault_get_opts_alias))}"
}

function _vault_get_opts_cftoken() {
  cat ${CFVAULT_ACCESS_PATH}/$(_vault_get_opts_alias)/cf_token
}

function _vault_get_opts_cftoken_header() {
  echo "cf-access-token=$(_vault_get_opts_cftoken)"
}

function _vault_http_opts_pos() {
  if [[ "$_vault_common_commands" == *"$1"* ]]; then
    echo 1
  elif [[ "$1" == "kv" && "$2" == "metadata" ]]; then
    echo 3
  else
    echo 2
  fi
}

function _vault_get_opts_commands() {
  pos=$(_vault_http_opts_pos $@)
  echo ${@:1:$pos}
}

function _vault_get_opts_args() {
  pos=$(_vault_http_opts_pos $@)
  rest=$(($pos + 1))
  echo ${@:$rest}
}

function _vault_cf_access() {
  addr=$(_vault_get_opts_address)
  if [[ ! -f ${CFVAULT_ACCESS_PATH}/$(_vault_get_opts_alias)/cf_token ]]; then
    cloudflared access login $addr
    cloudflared access token -app=$addr > ${CFVAULT_ACCESS_PATH}/$(_vault_get_opts_alias)/cf_token
  else
    echo "existing cf token found for $(_vault_get_opts_alias). Will use the cftoken. "
  fi
}

function cfvault_wrap() {
  wrap_token=$(_cfvault_wrap $@)
  echo "echo wrapped token: $wrap_token"
  echo "unwrap with:"
  echo "  vault unwrap ${wrap_token}"
  echo "or use $(_vault_get_opts_address)/ui/vault/tools/unwrap and put the wrapping token"
}

function _cfvault_wrap() {
  address="$(_vault_get_opts_address)"
  cf_token="$(_vault_get_opts_cftoken)"

  data=$(cfvault_get_wrap_data $@)
  result=$(curl -sX POST -H "X-Vault-Token: $(_vault_get_opts_token)" \
    -H "x-vault-wrap-ttl: 30m" \
    -H "cf-access-token: $cf_token" \
    "${address}/v1/sys/wrapping/wrap" -d "$data")
  echo "$result" | jq -r ".wrap_info.token"
}

function cfvault_get_wrap_data() {
  if [[ $1 == "kv" ]]; then
    cfvault kv get -format=json $2 | jq -c ".data.data"
  else
    echo $1
  fi
}

function cfvault_access() {
  VAULT_ROLE=""
  VAULT_ALIAS=$(_vault_get_opts_alias)
  VAULT_METHOD="oidc"
  RENEW_CREDENTIALS="false"

  while [ $# -gt 0 ] ; do
    case $1 in
      -a | --alias) VAULT_ALIAS="$2" ;;
      -m | --method) VAULT_METHOD="$2" ;;
      -r | --role) VAULT_ROLE="$2" ;;
      --renew) RENEW_CREDENTIALS=true;;
    esac
    shift
  done

  [[ -z $VAULT_ROLE ]] && [[ $VAULT_METHOD == "oidc" ]] && echo "-r, --role is required when method is oidc" && exit 1
  [[ -z $VAULT_ALIAS ]] && printf "target vault alias is required (-a or --alias). available aliases: \n$(ls ${CFVAULT_ALIASES_PATH})" && exit 1
  alias_exists=$(ls ${CFVAULT_ALIASES_PATH} | grep -w "$VAULT_ALIAS")
  if [[ -z $alias_exists ]]; then
    printf "unknown alias $VAULT_ALIAS. Supported:\n$(ls ${CFVAULT_ALIASES_PATH})"
    return 1
  fi
  if [[ $RENEW_CREDENTIALS == true ]]; then
    echo "Renewing credentials. Removing tokens in $(realpath "${CFVAULT_ACCESS_PATH}/$VAULT_ALIAS")"
    [[ -d ${CFVAULT_ACCESS_PATH}/$VAULT_ALIAS ]] && rm -rf "${CFVAULT_ACCESS_PATH:?}/$VAULT_ALIAS"
  fi

  mkdir -p "${CFVAULT_ACCESS_PATH}/$VAULT_ALIAS"

  echo "$VAULT_ALIAS" > ${CFVAULT_ALIAS_FILE_PATH}
  export VAULT_ALIAS=${VAULT_ALIAS}

  _vault_cf_access
  _vault_login
}

function cfvault_ui() {
  token_data=$(cfvault token lookup -format=json | jq ".data + {client_token: .data.id}")
  [[ -n ${CFVAULT_DEBUG} ]] && echo "wrapping token data: ${token_data}"
  wrap_token=$(_cfvault_wrap "$token_data")
  echo "$(_vault_get_opts_address)/ui/vault/auth?with=token&wrapped_token=${wrap_token}"
}

function cfvault() {
  if [[ "$1" == "wrap" ]]; then
    cfvault_wrap ${@:2}
  elif [[ "$1" == "access" ]]; then
    cfvault_access ${@:2}
  elif [[ "$1" == "ui" ]]; then
    cfvault_ui
  else
    vault_args="$(_vault_get_opts_commands $@) -address="$(_vault_get_opts_address)" -header="$(_vault_get_opts_cftoken_header)" $(_vault_get_opts_args $@)"
    if [[ -n $CFVAULT_DEBUG ]]; then
      echo "VAULT_ALIAS=$(_vault_get_opts_alias)"
      echo "VAULT_ADDR=$(_vault_get_opts_address)"
      echo "vault $vault_args"
    fi
    eval "VAULT_TOKEN=$(_vault_get_opts_token) vault $vault_args"
  fi
}

# ohmyzsh support
function cfvault_prompt_info() {
  info=""
  [[ $CFVAULT_PROMPT_SHOW_ALIAS != false ]] && info="${info}a=$(_vault_get_opts_alias);"
  [[ -n $info ]] && echo "<cfv:${info:0:-1}>"
}

if [[ "$CFVAULT_PROMPT_SHOW" != false && "$RPROMPT" != *'$(cfvault_prompt_info)'* ]]; then
  RPROMPT='$(cfvault_prompt_info)'"$RPROMPT"
fi

complete -o nospace -C /opt/homebrew/bin/vault cfvault
