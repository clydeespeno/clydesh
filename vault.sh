_vault_common_commands="read write delete list login status unwrap"

CFVAULT_ALIASES_PATH=${CFVAULT_ALIASES_PATH:-"$HOME/.vault_aliases"}
CFVAULT_DB_ALIASES_PATH=${CFVAULT_ALIASES_PATH:-"$HOME/.vault_db_aliases"}
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

function cfvault_db() {
  args=( "${@:2}" )
  _db_type="$1"

  if [[ "pg postgres" == *"$_db_type"* ]]; then
    cfvault_db_postgres $args
  elif [[ "astra-classic cassandra" == *"$_db_type"* ]]; then
    cfvault_db_astra_classic $args
  fi
}

function cfvault_db_astra_classic() {
  _access="read"
  _cqlsh="false"
  while [ $# -gt 0 ] ; do
    case $1 in
      -a | --access) _access="$2"; shift ;;
      --cqlsh) _cqlsh="true"; ;;
      -b | --bundle) _bundle="$2"; shift ;;
      *) _db_name="$1" ;;
    esac
    shift
  done

  _bundle=${_bundle:-"${_db_name}-secure-bundle.zip"}

  echo "Creating credentials for astra-classic ${_db_name} with ${_access} access"
  _creds=$(cfvault read -format=json astra-classic/creds/${_db_name}-${_access})
  echo "These are you credentials:"
  echo "$_creds" | jq ".data"
  echo ""
  echo "Renew this lease by:"
  echo "cvault lease renew astra-classic/creds/${_db_name}-${_access}/$(echo "$_creds" | jq -r ".lease_id")"
  echo ""

  username=$(echo $_creds | jq -r ".data.username")
  password=$(echo $_creds | jq -r ".data.password")

  if [[ $_cqlsh != false ]]; then
    if [[ ! -f "$_bundle" ]]; then
      echo "Getting bundle from vault at platform/database-access/astra-classic/${_db_name}"
      cfvault kv get -format=json platform/database-access/astra-classic/${_db_name} | jq -r '.data.data["secure-bundle.zip"]' | base64 -d > $_bundle
      echo "Bundle is written at $_bundle"
    else
      echo "Bundle already exists at $_bundle. Not downloading."
    fi

    cqlsh -b $_bundle -u "${username}" -p "${password}"
  else
    echo "To connect to the database, get the bundle first by running: "
    echo "cfvault kv get -format=json platform/database-access/astra-classic/${_db_name} | jq -r '.data.data[\"secure-bundle.zip\"]' | base64 -d > $_bundle"
    echo ""
    echo "Use cqlsh or any tools to connect to it."
    echo "cqlsh -b $_bundle -u \"${username}\" -p \"${password}\""
  fi
}

function cfvault_db_postgres() {
  _access="read"
  _proxy="false"
  _psql="false"
  _proxy_port="15432"
  while [ $# -gt 0 ] ; do
    case $1 in
      -a | --access) _access="$2"; shift ;;
      --proxy) _proxy="true"; ;;
      --psql) _psql="true"; ;;
      -p | --port) _proxy_port="$2"; shift ;;
      *) _db_name="$1" ;;
    esac
    shift
  done

  echo "Creating credentials for postgres ${_db_name} with ${_access} access"
  _creds=$(cfvault read -format=json postgres/creds/${_db_name}-${_access})
  echo "These are you credentials:"
  echo "$_creds" | jq ".data"
  echo ""
  echo "Renew this lease by:"
  echo "cvault lease renew postgres/creds/${_db_name}-${_access}/$(echo "$_creds" | jq -r ".lease_id")"
  echo ""

  metadata=$(cfvault kv get -format=json platform/database-access/postgres/${_db_name})
  url=$(echo $metadata | jq -r ".data.data.url")
  username=$(echo $_creds | jq -r ".data.username")
  password=$(echo $_creds | jq -r ".data.password")
  db=$(echo $metadata | jq -r ".data.data.db")

  # create a proxy that runs in the background if --proxy is passed
  if [[ $_proxy == true ]]; then
    cloudflared access tcp --hostname "$url" --url localhost:$_proxy_port &
    proc_pid=$!
    echo "Running the tcp proxy for $url in the background on port $_proxy_port"
    echo "To kill the proxy run:"
    echo "kill -9 $proc_pid"

    # if psql is true, and proxy is running, also run the psql command with the provided credentials
    if [[ $_psql == true ]]; then
      psql "postgres://${username}:${password}@localhost:$_proxy_port/${db}"
    fi
  # if no proxy is specified, give instructions on how to access the application.
  else
    echo "Since --proxy is not supplied, you will need to manually run the proxy to access ${_db_name} locally. Run:"
    echo "cloudflared access tcp --hostname $url --url localhost:$_proxy_port"
    echo ""
    echo "Once the proxy is running, you can also run psql or any other tools to connect to it."
    echo "psql \"postgres://${username}:${password}@localhost:$_proxy_port/${db}\""
  fi
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
  elif [[ "$1" == "db" ]]; then
    cfvault_db ${@:2}
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

autoload colors; colors;
export LSCOLORS="Gxfxcxdxbxegedabagacad"
setopt prompt_subst

function _cfcol() {
  _prefix="%{$reset_color%}%{$fg[yellow]%}"
  _suffix="%{$reset_color%}"
  echo "${_prefix}${1}${_suffix}"
}

CFVAULT_PROMPT_SHOW_ALIAS=true
CFVAULT_PROMPT_DISABLE_LINK=true

function _cflink() {
  alias="$(_vault_get_opts_alias)"
  if [[ $CFVAULT_PROMPT_DISABLE_LINK != true ]]; then
    address="$(_vault_get_opts_address)"
    printf '\033]8;;%s\033\\%s\033]8;;\033\\\n' "$address" " $alias "
  else
    echo " $alias "
  fi
}

# ohmyzsh support
function cfvault_prompt_info() {
  if [[ $CFVAULT_PROMPT_SHOW != false ]]; then
    [[ $CFVAULT_PROMPT_SHOW_ALIAS != false ]] && info="${info}$(_cflink);"
    [[ -n $info ]] && echo "$(_cfcol "cfv:(")${info:0:-1}$(_cfcol ")") "
  fi
}

if [[ "$CFVAULT_PROMPT_SHOW" != false && "$PROMPT" != *'$(cfvault_prompt_info)'* ]]; then
  PROMPT="$PROMPT"'$(cfvault_prompt_info)'
fi

complete -o nospace -C /opt/homebrew/bin/vault cfvault
