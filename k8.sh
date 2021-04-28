export KUBE_NAMESPACE="default"
[ -f "$HOME/.kubenamespace" ] && export KUBE_NAMESPACE=`cat $HOME/.kubenamespace`

export KUBE_PORT_ALIAS_FILE=${KUBE_PORT_ALIAS_FILE:-$HOME/.kubeportaliases}

export KUBE_NAMESPACE_CLUSTER_ALIAS_FILE=${KUBE_NAMESPACE_CLUSTER_ALIAS_FILE:-$HOME/.kubenamespaceclusteraliases}

function k-ns() {
  if [ -n "$1" ]; then
    echo "$1" > ~/.kubenamespace
    echo "switched to namespace \"$1\""
    export KUBE_NAMESPACE="$1"
  else
    cat ~/.kubenamespace
  fi
}

function kn() {
  kubectl -n `cat ~/.kubenamespace` $@
}

function k-ex() {
  kn exec -it $@
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
    cluster=$(echo $ns_alias | awk '{print $2}')
    ns=$(echo $ns_alias | awk '{print $3}')
    k-cluster $cluster
    k-ns $ns
  fi
}

function k-dep() {
  kn get deploy $@
}

function k-xdep() {
  kn delete deploy $@
}

function k-dep-apply() {
  deps=$(k-dep -l "$1" | tail +2 | awk '{print $1;}')

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
  service=${1:-"."}
  watch -n 1 "kubectl -n $KUBE_NAMESPACE get pods ${@:2} | grep \"$service\""
}

function k-watch-l() {
  watch -n 1 "kubectl -n $KUBE_NAMESPACE get pods -l $1"
}

function k-sec64() {
  all_data=$(k-sec $1 -o json | jq -r ".data")
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
  all_data=$(k-sec $1 -o json | jq -r ".data")
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
  donecreating=false
  while [[ $donecreating == "false" ]]; do
    cr=$(k-pod | grep "$rshash" | grep "Creating" | head)
    [ -z $cr ] && donecreating=true
    [[ $donecreating == "false" ]] && echo "Still creating, $(k-pod | grep "$rshash" | head)" && sleep 1
  done

  up=false
  while [[ $up == "false" ]]; do
    down=$(k-pod | grep "$rshash" | grep "0/" | head)
    [ -z $down ] && up=true
    [[ $up == "false" ]] && echo "Still restarting, retrying in 1 sec (down = $(echo "$down" | awk '{print $1": "$2}'))" && sleep 1
  done
  echo ""
}

function k-cluster() {
  local context=$1
  if [ -z "$context" ]; then
    kubectl config current-context
  else
    kubectl config use-context $context
  fi
}

function k-ap() {
  kubectl apply -f $1
}

function _k_ns_completion() {
  local namespaces=`kubectl get namespaces | tail -n +2 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$namespaces"))
  return 0
}

function _k_pod_completion() {
  local services=`kn get pods | tail -n +2 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$services"))
  return 0
}

function _k_yaml_completion() {
  local files=$(ls -p | grep "\.yaml")
  COMPREPLY=($(compgen -W "$files"))
  return 0
}

function _k_deploy_completion() {
  local deploys=`kn get deploy | tail -n +2 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$deploys"))
  return 0
}

function _k_service_completion() {
  local servs=`kn get service | tail -n +2 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$servs"))
  return 0
}

function _k_secret_completion() {
  local secrets=`kn get secret | tail -n +2 | awk '{print $1;}'`
  COMPREPLY=($(compgen -W "$secrets"))
  return 0
}

function _k_sec64_completion() {
  local reply=""
  if [ ${COMP_CWORD} == "1" ]; then
    reply=$(kn get secret | tail -n +2 | awk '{print $1;}')
    COMPREPLY=($(compgen -W "$reply"))
  elif [ ${COMP_CWORD} == "2" ]; then
    local secret=${COMP_WORDS[1]}
    all_data=$(k-sec $secret -o json | jq -r ".data")
    COMPREPLY=($(echo "$all_data" | jq "keys[]" -r))
  fi
  return 0
}


function _k_cluster_completion() {
  local clusters=`kubectl config view -o json | jq -r '.contexts[].name'`
  COMPREPLY=($(compgen -W "$clusters"))
  return 0
}

function _k_fwd_completion() {
  local reply=""
  if [ ${COMP_CWORD} == "1" ]; then
    reply=$(kn get pods | tail -n +2 | awk '{print $1;}')
  else if [ ${COMP_CWORD} == "2" ]
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

complete -F _k_ns_completion k-ns
complete -F _k_pod_completion k-bash k-sh k-ex k-log k-pod k-dpod k-xpod
complete -F _k_deploy_completion k-dep k-ddep k-xdep k-scale-dep k-xdep-scale k-dep-rs k-dep-restart
complete -F _k_service_completion k-ser k-dser
complete -F _k_secret_completion k-sec k-dsec k-sec-mount
complete -F _k_sec64_completion k-sec64
complete -F _k_cluster_completion k-cluster
complete -F _k_fwd_completion k-fwd
complete -F _ks_completion ks
