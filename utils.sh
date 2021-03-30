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

parentenv
localenv
