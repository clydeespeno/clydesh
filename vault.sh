_vault_common_commands="read write delete list login status unwrap"
_vault_other_commands="audit auth debug kv lease monitor namespace operator path-help plugin policy print secrets ssh token"

function vault_http_opts_pos() {
  if [[ "$_vault_common_commands" == *"$1"* ]]; then
    echo 1
  else
    echo 2
  fi
}

function cfvault_wrap() {
  address="$(cat ~/.vault_access | awk '{print $1}')"
  cf_token="$(cat ~/.vault_access | awk '{print $2}')"

  data=$(cfvault_get_wrap_data $@)

  result=$(curl -sX POST -H "X-Vault-Token: $(vault print token)" \
    -H "x-vault-wrap-ttl: 30m" \
    -H "Cf-Access-Token: $cf_token" \
    "${address}/v1/sys/wrapping/wrap" -d "$data")
  echo "$result" | jq ".wrap_info.token" | xargs -n 1 -I {} bash -c 'echo wrapped token: {}'
  echo "unwrap with:"
  echo "  vault unwrap $(echo "$result" | jq -r ".wrap_info.token")"
  echo "or use ${address}/ui/vault/tools/unwrap and put the wrapping token"
}

function cfvault_get_wrap_data() {
  if [[ $1 == "kv" ]]; then
    cfvault kv get -format=json $2 | jq -c ".data.data"
  else
    echo $1
  fi
}

function cfvault_access() {
  vault_alias=$(cat ~/.vault_alias | grep "^$1\s")
  if [[ -n $vault_alias ]]; then
    export VAULT_ADDR=$(echo $vault_alias | awk '{print $2}')
  else
    export VAULT_ADDR=$1
  fi
  cloudflared access login $VAULT_ADDR
  export CF_VAULT_ACCESS_TOKEN=$(cloudflared access token -app=$VAULT_ADDR)
  echo "$VAULT_ADDR $CF_VAULT_ACCESS_TOKEN" >~/.vault_access
}

function cfvault() {
  if [[ "$1" == "wrap" ]]; then
    cfvault_wrap ${@:2}
  elif [[ "$1" == "access" ]]; then
    cfvault_access ${@:2}
  else
    pos=$(vault_http_opts_pos $1)
    rest=$(($pos + 1))
    address="$(cat ~/.vault_access | awk '{print $1}')"
    cf_token="$(cat ~/.vault_access | awk '{print $2}')"
    vault_cmd="vault ${@:1:$pos} -address=\"$address\" -header=\"cf-access-token=${cf_token}\" ${@:$rest}"
    if [[ -n $CF_VAULT_DEBUG ]]; then
      echo $vault_cmd
    fi
    eval "$vault_cmd"
  fi
}

complete -o nospace -C /opt/homebrew/bin/vault cfvault
