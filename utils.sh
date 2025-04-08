workspace () {
  cd ~/workspace/$1
}

export PARENT_ENV_FILE=.parentenv
export LOCAL_ENV_FILE=.localenv

# DEPRECATED. Use direnv
loadfile () {
  filepath=$1
  msg=$2
  if [ -f $1 ]
  then
    echo $msg;
    source $filepath;
  fi
}

# DEPRECATED. Use direnv
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

cwdiff () {
  wdiff -n -w $'\033[30;41m' -x $'\033[0m' -y $'\033[30;42m' -z $'\033[0m' $@
}

# text utilities, underline, bold, color
function t-und() {
  echo "$(tput smul)$*$(tput sgr0)"
}

function t-bold() {
  echo "$(tput bold)$*$(tput sgr0)"
}

function t-red() {
  echo "$(tput setaf 1)$*$(tput sgr0)"
}

function t-yellow() {
  echo "$(tput setaf 3)$*$(tput sgr0)"
}

function t-green() {
  echo "$(tput setaf 2)$*$(tput sgr0)"
}

function uncolor() {
  echo "$1" | sed -r "s/\x1B(\[[0-9;]*[JKmsu]|\(B)//g"
}


parentenv
localenv
