_packagenode() {
  node -e 'var e = require("./package.json").engines; console.log(e && e.node ? e.node.replace(/[^\d\.]+/g, "") : "" )'
}

_nodeversion() {
  local v
  if [ -e ".nvmrc" ]; then
    v=`cat .nvmrc`
  elif [ -e "package.json" ]; then
    v=$(_packagenode)
  fi

  if [ -z "$v" ]; then
    remoteversion=`nvm ls-remote | awk 'END{print}'`
    v=`echo $remoteversion | gsed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"`
    v=`echo ${v#->} | awk '{$1=$1}1'`
  fi

  echo `echo $v | tr -d v`
}

_sameversion() {
  local current="$(node -v | tr -d v)"
  local wanted="$(echo $1 | tr -d v)"
  [ "$current" = "$wanted" ] && echo "true";
}

createnvmrc() {
  [[ ! -e ".nvmrc"  && ( ! -e "package.json"  ||  -e "package.json" &&  -z "`_packagenode`" ) ]] && echo $1 > .nvmrc
}

nvmrc() {
  local nodev=`_nodeversion`
  local issame=`_sameversion ${nodev}`
  echo "determined nodeversion $nodev"
  if [ -z "$issame" ]; then
    echo "node version in use doesn't match what we wanted to install. Installing node $nodev"
    nvm install $nodev
  fi
  createnvmrc $nodev
}

nvmupdate() {
  local currdir=$PWD
  cd $NVM_DIR
  git pull
  cd $currdir
}

alias lt='lt'
