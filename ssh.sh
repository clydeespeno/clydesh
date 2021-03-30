export JUMP_HOST=${JUMP_HOST:-jumphost}
export MOSH_BASTION_HOST=${JUMP_HOST}
export MOSH_BASTION_SSH_KEY=${MOSH_BASTION_SSH_KEY}
export MOSH_BASTION_SSH_USER=${MOSH_BASTION_SSH_USER}

function tunnel() {
  local hostname=$1
  local parsed=$(_parseport $2)
  local local_port=${parsed%:*}
  local forward_port=${parsed#*:}
  local opts=${@:3}
  echo "ssh -N ${JUMP_HOST} -L ${local_port}:${hostname}:${forward_port} ${opts}"
  ssh -N ${JUMP_HOST} -L ${local_port}:${hostname}:${forward_port} ${opts}
}

function mosh() {
  command mosh ${MOSH_BASTION_HOST} -- ssh -i ${MOSH_BASTION_SSH_KEY} ${MOSH_BASTION_SSH_USER}@$1
}

