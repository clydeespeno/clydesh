# bitbucket api helpers

mkdir -p "${CLYDESH_HOME}"/.alias/bb
mkdir -p "${CLYDESH_HOME}"/.creds/bb

function bb() {
  cmd=$1
  if [[ ! -f "${CLYDESH_HOME}/bb_${cmd}.sh" ]]; then
    echo "unknown command '$cmd'"
    echo "supported commands: "
    for c in "${CLYDESH_HOME}"/bb/bb_*; do
      echo "  $(echo $c | sed -E 's/.*bb_(.*).sh/\1/g')"
    done
  else
    ${CLYDESH_HOME}/bb_${cmd}.sh ${@:2}
  fi
}
