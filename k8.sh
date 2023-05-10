export KUBE_NAMESPACE="default"
export KUBE_CONTEXT=$(kubectl config current-context)

[ -f "$HOME/.kubenamespace" ] && export KUBE_NAMESPACE=`cat $HOME/.kubenamespace`
[ -f "$HOME/.kubecontext" ] && export KUBE_CONTEXT=`cat $HOME/.kubecontext`

export KUBE_PORT_ALIAS_FILE=${KUBE_PORT_ALIAS_FILE:-$HOME/.kubeportaliases}

export KUBE_NAMESPACE_CLUSTER_ALIAS_FILE=${KUBE_NAMESPACE_CLUSTER_ALIAS_FILE:-$HOME/.kubenamespaceclusteraliases}

function k() {
  kubectl --context=${KUBE_CONTEXT} $@
}

function k-ns() {
  if [ -n "$1" ]; then
    echo "$1" > ~/.kubenamespace
    echo "switched to namespace \"$1\""
    export KUBE_NAMESPACE="$1"
  else
    echo $KUBE_NAMESPACE
  fi
}

function k-ctx() {
  if [ -n "$1" ]; then
    echo "$1" > ~/.kubecontext
    echo "switched to context \"$1\""
    export KUBE_CONTEXT="$1"
  else
    echo $KUBE_CONTEXT
  fi
}

function kn() {
  echo "kubectl -n $KUBE_NAMESPACE --context $KUBE_CONTEXT $@"
  kubectl -n $KUBE_NAMESPACE --context $KUBE_CONTEXT $@
}

function k-ex() {
  kn exec -it $1 -- ${@:2}
}

function k-bash() {
  k-ex $@ bash
}

function k-sh() {
  k-ex $@ sh
}

function k-log() {
  kn logs $@
}

function k-pod() {
  kn get pods $@
}

function k-dpod() {
  kn describe pod $@
}

function k-xpod() {
  kn delete pod $@
}

function k-pod-reload() {
  pods=$(k-pod -l "$1" | tail +2 | awk '{print $1;}')
  for pod in $(compgen -W "$pods"); do
    echo "deleting pod $pod"
    k-xpod $pod
    up=false
    while [[ $up == "false" ]]; do
      down=$(k-pod | grep "${pod%-*}" | grep "0/" | head)
      [ -z $down ] && up=true
      [[ $up == "false" ]] && echo "Still restarting, retrying in 1 sec (down = $(echo "$down" | awk '{print $1": "$2}'))" && sleep 1
    done
    echo ""
  done
}

function _parseport() {
  parsed=$(cat ${KUBE_PORT_ALIAS_FILE} | grep -w $1 | head -1 | awk '{print $2}')
  if [ -z "$parsed" ]; then
    [[ "$1" == *":"* ]] && parsed="$1" || parsed="$1:$1"
  fi
  echo $parsed
}

function k-fwd() {
  port=$(_parseport $2)
  kn port-forward $1 $port
}

function ks() {
  ns_alias=$(cat ${KUBE_NAMESPACE_CLUSTER_ALIAS_FILE} | grep "^$1\s")
  if [ -z "$ns_alias" ]; then
    echo "unknown namespace cluster alias $1"
  else
    ctx=$(echo $ns_alias | awk '{print $2}')
    ns=$(echo $ns_alias | awk '{print $3}')
    k-ctx $ctx
    k-ns $ns
  fi
}

function k-dep() {
  kn get deploy $@
}

function k-dep-container() {
  container_name=$2
  dep=$(kn get deploy $1 -o yaml | tail +2)
  if [[ -z $container_name ]]; then
    echo $dep | yq -P e ".spec.template.spec.containers[0]" -
  else
    echo $dep | yq -P e ".spec.template.spec.containers[] | select(.name == \"${container_name}\")"
  fi
}

function k-dep-image() {
  k-dep-container $1 $2 | yq -P e ".image" -
}

# get pods of a node
function k-npod() {
  k-pod -A --field-selector=spec.nodeName=$1
}

function k-dep-env() {
  container=$(k-dep-container $1 $2)
  # print envs from env property
  for env in $(echo $container | yq -P e ".env[].name" -); do
    env_map=$(echo $container | yq -P e ".env[] | select(.name == \"$env\")" -)
    if [[ $(echo $env_map | yq -P e ".value" -) != "null" ]]; then
      echo "$env=$(echo $env_map | yq -P e ".value" -)"
    fi

    if [[ $(echo $env_map | yq -P e ".valueFrom" -) != "null" ]]; then
      value_from=$(echo $env_map | yq -P e ".valueFrom" -)
      if [[ $(echo $value_from | yq -P e ".secretKeyRef" -) != "null" ]]; then
        sec_name=$(echo $value_from | yq -P e ".secretKeyRef.name" -)
        sec_key=$(echo $value_from | yq -P e ".secretKeyRef.key" -)
        echo "**secret-from:$sec_name;$sec_key** $env=$(k-sec-value $sec_name $sec_key)"
      fi
      if [[ $(echo $value_from | yq -P e ".configMapKeyRef" -) != "null" ]]; then
        cm_name=$(echo $value_from | yq -P e ".configMapKeyRef.name" -)
        cm_key=$(echo $value_from | yq -P e ".configMapKeyRef.key" -)
        echo "$env=$(k-cm-value $cm_name $cm_key)"
      fi
    fi
  done

  # render secrets in envFrom
  for sec in $(echo $container | yq -P e '.envFrom[] | select(has("secretRef")) | .secretRef.name' -); do
    all_data=$(k-sec $sec -o json | tail -n +2 | jq -r ".data")
    keys=($(echo "$all_data" | jq "keys[]" -r))
    for k in $keys; do
      echo "**secret-from:$sec;$k** $k=$(echo $all_data | jq ".[\"$k\"]" -r | base64 --decode)"
    done
  done

  # render secrets in envFrom
  for cm in $(echo $container | yq -P e '.envFrom[] | select(has("configMapRef")) | .configMapRef.name' -); do
    all_data=$(kng cm $cm -o json | tail -n +2 | jq -r ".data")
    keys=($(echo "$all_data" | jq "keys[]" -r))
    for k in $keys; do
      echo "$k=$(echo $all_data | jq ".[\"$k\"]" -r)"
    done
  done
}

function k-sec-value() {
  k-sec $1 -o json | tail -n +2 | jq -r ".data[\"$2\"]" | base64 -d
}

function k-cm-value() {
  kng cm $1 -o json | tail -n +2 | jq -r ".data[\"$2\"]"
}

function k-xdep() {
  kn delete deploy $@
}

function k-dep-apply() {
  deps=$(k-dep -l "$1" | tail +3 | awk '{print $1;}')

  for dep in $(compgen -W "$deps"); do
    $2 $dep ${@:3}
  done
}

function k-scale-dep() {
  kn scale deployment/$1 --replicas=$2
}

function k-xdep-scale() {
  k-scale-dep $1 0
  echo "deployment $1 is scaled down to 0. Press ENTER to delete deployment"
  read
  k-xdep $1
}

function k-ddep() {
  kn describe deploy $@
}

function k-ser() {
  kn get service $@
}

function k-dser() {
  kn describe service $@
}

function k-sec() {
  kn get secret $@
}

function k-dsec() {
  kn describe secret $@
}

function k-watch() {
  if [ -z $1 ]; then
    service="."
  else
    service=""
    if [ -f $1 ]; then
      tmp=( $(< "$1") )
      for ser in $tmp; do
        service="$ser|$service"
      done
    else
      for ser in "$@"; do
        service="$ser|$service"
      done
    fi
    service=$(echo $service | awk '{print substr( $0, 1, length($0)-1)}')
    echo "watching services $service"
  fi
  watch -n 1 "kubectl -n $KUBE_NAMESPACE get pods | grep -E \"$service\""
}

function k-watch-l() {
  watch -n 1 "kubectl -n $KUBE_NAMESPACE get pods -l $1"
}

function k-sec64() {
  all_data=$(k-sec $1 -o json | tail -n +2 | jq -r ".data")
  if [ -z "$2" ]; then
    keys=($(echo "$all_data" | jq "keys[]" -r))
    for k in $keys; do
      echo "$k:"
      echo $all_data | jq ".[\"$k\"]" -r | base64 --decode
      echo ""
      echo ""
    done
  else
    echo $all_data | jq ".[\"$2\"]" -r | base64 --decode
  fi
}

function k-sec-mount() {
  all_data=$(k-sec $1 -o json | tail -n +2 | jq -r ".data")
  dir=${2:-$(pwd)}
  mkdir -p $dir 
  
  keys=($(echo "$all_data" | jq "keys[]" -r))

  for k in $keys; do
    echo "mounting $k to $dir/$k"
    echo $all_data | jq ".[\"$k\"]" -r | base64 --decode > $dir/$k
  done
}

function k-dep-rs() {
  revision=$(k-dep $1 -o json | jq -r '.metadata.annotations["deployment.kubernetes.io/revision"]')
  template=$(kn rollout history deployment/$1 --revision=${revision} | grep pod-template-hash)
  hash=${template#*=}
  echo "$1-$hash"  
}

function k-dep-restart() {
  kn rollout restart deployment/$1

  sleep 2
  rshash=`k-dep-rs $1`

  echo "new replica set is $rshash"
}

function k-dep-rescale() {
  rs=$(k-dep $1 -o yaml | tail -n +2 | yq -P e ".spec.replicas" -)
  k-scale-dep $1 0
  k-scale-dep $1 $rs 
}

function k-ap() {
  kubectl apply -f $1
}

function k-sec-env() {
  all_data=$(k-sec $1 -o json | jq -r ".data")
  keys=($(echo "$all_data" | jq "keys[]" -r))
  for k in $keys; do
    if [ $# -eq 1 ] || [[ "$*" == *"$k"* ]]; then
      echo "exporting $k"
      eval "export $k=$(echo $all_data | jq ".[\"$k\"]" -r | base64 --decode)"
    fi
  done
}

function knd() {
  kn describe $@
}

function kd() {
  k describe $@
}

function kng() {
  kn get $@
}

function kg() {
  k get $@
}

function knx() {
  kn delete $@
}

function kx() {
  k delete $@
}

function kne() {
  kn edit $@
}

function ke() {
  k edit $@
}

function _k_ns_completion() {
  local namespaces=`kubectl --context $KUBE_CONTEXT get namespaces | tail -n +2 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$namespaces"))
  return 0
}

function _k_pod_completion() {
  local services=`kn get pods | tail -n +3 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$services"))
  return 0
}

function _k_yaml_completion() {
  local files=$(ls -p | grep "\.yaml")
  COMPREPLY=($(compgen -W "$files"))
  return 0
}

function _k_deploy_completion() {
  local deploys=`kn get deploy | tail -n +3 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$deploys"))
  return 0
}

function _k_service_completion() {
  local servs=`kn get service | tail -n +3 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$servs"))
  return 0
}

function _k_secret_completion() {
  local secrets=`kn get secret | tail -n +3 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$secrets"))
  return 0
}

function _k_sec64_completion() {
  local reply=""
  if [ ${COMP_CWORD} == "1" ]; then
    reply=$(kn get secret | tail -n +3 | awk '{print $1;}')
    COMPREPLY=($(compgen -W "$reply"))
  elif [ ${COMP_CWORD} == "2" ]; then
    local secret=${COMP_WORDS[1]}
    all_data=$(k-sec $secret -o json | jq -r ".data")
    COMPREPLY=($(echo "$all_data" | jq "keys[]" -r))
  fi
  return 0
}


function _k_ctx_completion() {
  local ctxs=`kubectl config view -o json | jq -r '.contexts[].name'`
  COMPREPLY=($(compgen -W "$ctxs"))
  return 0
}

function _k_fwd_completion() {
  local reply=""
  if [ ${COMP_CWORD} == "1" ]; then
    reply=$(kn get pods | tail -n +3 | awk '{print $1;}')
  elif [ ${COMP_CWORD} == "2" ]; then
    reply=$(cat $KUBE_PORT_ALIAS_FILE | awk '{print $1}')
  fi
  COMPREPLY=($(compgen -W "$reply"))
  return 0
}

function _ks_completion() {
  reply=$(cat $KUBE_NAMESPACE_CLUSTER_ALIAS_FILE | awk '{print $1;}')
  COMPREPLY=($(compgen -W "$reply"))
  return 0
}

function _k_resource_completion() {
  local reply=""
  if [ ${COMP_CWORD} == "1" ]; then
    reply=$(k  api-resources --verbs=list | tail -n +2 | awk '{print $1}')
  elif [ ${COMP_CWORD} == "2" ]; then
    reply=$(kn get ${COMP_WORDS[$COMP_CWORD-1]} | tail -n +3 | awk '{print $1}')
  fi
  COMPREPLY=($(compgen -W "$reply"))
  return 0
}

function _k_node_completion() {
  local nodes=`kn get nodes | tail -n +3 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$nodes"))
  return 0
}

complete -F _k_ns_completion k-ns
complete -F _k_pod_completion k-bash k-sh k-ex k-log k-pod k-dpod k-xpod
complete -F _k_deploy_completion k-dep k-ddep k-xdep k-scale-dep k-xdep-scale k-dep-rs k-dep-restart k-dep-rescale k-dep-env k-dep-container k-dep-image
complete -F _k_service_completion k-ser k-dser
complete -F _k_secret_completion k-sec k-dsec k-sec-mount k-sec-env
complete -F _k_sec64_completion k-sec64
complete -F _k_ctx_completion k-ctx
complete -F _k_fwd_completion k-fwd
complete -F _ks_completion ks
complete -F _k_resource_completion knd kng knx kd kg kx kne ke
complete -F _k_node_completion k-npod