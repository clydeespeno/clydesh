dockbash() {
  docker exec -it $1 bash
}

dockstop() {
  docker stop $1
}

_dockbash_completion() {
  local images
  images=`docker ps | awk 'FNR > 1 {print $NF}'`
  COMPREPLY=($(compgen -W "$images"))
  return 0
} && complete -F _dockbash_completion dockbash dockstop

