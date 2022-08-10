workspace () {
  cd ~/workspace/$1
}

export PARENT_ENV_FILE=.parentenv
export LOCAL_ENV_FILE=.localenv

loadfile () {
  filepath=$1
  msg=$2
  if [ -f $1 ]
  then
    echo $msg;
    source $filepath;
  fi
}

parentenv () {
  _IFS=${IFS}
  IFS="/"
  path_tokens=($(pwd))
  curr_path=""
  for p in $path_tokens; do
    curr_path="$curr_path/$p"
    parent_env_file=$curr_path/$PARENT_ENV_FILE
    loadfile $parent_env_file "loading file $PARENT_ENV_FILE from $parent_env_file";
  done
  IFS=${_IFS}
}

get_gr() {
  _IFS=${IFS}
  IFS="/"
  path_tokens=($(pwd))
  curr_path=""
  root="$(pwd)"
  for p in $path_tokens; do
    curr_path="$curr_path/$p"
    if [ -d "$curr_path/.git" ] && [ "$curr_path" != "$root" ] ; then
      root=$curr_path
    fi
  done
  IFS=${_IFS}
  echo $root
}

cd_gr() {
  cd $(get_gr)/$1
}

localenv () {
  loadfile ./$LOCAL_ENV_FILE "loading file $LOCAL_ENV_FILE"
}

cdl () {
  cd $1
  parentenv
  localenv
}

grenv () {
  env | grep $1
}

sourceload () {
  profile=~/.profile
  case "$SHELL" in
    /bin/bash )
      profile=~/.bash_profile
      ;;
    /bin/zsh )
      profile=~/.zshrc
      ;;
    /bin/fish )
      profile=/.config/fish/config.fish
      ;;
    * )
      profile=~/.profile
      ;;
  esac
  echo "reloading $profile"
  source $profile
}

complete_ls() {
  cwd=$PWD
  dir=$cwd/$1
  function _complete_ls() {
    local comp=$(ls $dir)
    COMPREPLY=($(compgen -W "$comp"))
    return 0
  }

  complete -F _complete_ls ${@:2}
}

_complete_cd_gr() {
  cwd=$(pwd)
  gr=$(get_gr)
  target=$gr/${COMP_WORDS[COMP_CWORD]}
  if [ -d "$target" ]; then
    cd $target
  else
    cd $gr
  fi
 
  COMPREPLY=( $(compgen -d) )
  cd $cwd
  return 0
}

complete -F _complete_cd_gr cd_gr

cwdiff () {
  wdiff -n -w $'\033[30;41m' -x $'\033[0m' -y $'\033[30;42m' -z $'\033[0m' $@
}

parentenv
localenv
