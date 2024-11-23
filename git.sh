alias gitrmbranch='git branch -r | awk "{print $1}" | egrep -v -f /dev/fd/0 <(git branch -vv | grep origin) | awk "{print $1}" | xargs git branch -d'
alias gpom='git pull --rebase origin master'
alias gs='git status'
alias glog='git log --graph --oneline --decorate --date=relative --all'
alias gaddmit='git add .; git commit -m'

gitf() {
  git checkout -b feature/$1
}

gitDeployTags() {
  git tag --points-at HEAD | grep d-*-*
}

git-dtags() {
  a=( $(gitDeployTags) )
  for tag in "${a[@]}"; do
    echo $tag
  done
}

hasAll() {
  case $1 in "d-ALL-"*) return 0 ;; esac
  return 1
}

gitCountries() {
  a=( $(gitDeployTags) )
  local tmp
  for tmp in "${a[@]}"; do
    c=$(echo $tmp | awk -F "-" '/d/{print $2}')
    echo $c
  done
}

git-hasall() {
  a=( $(gitDeployTags) )
  if hasAll "${a[@]}"; then echo "y"; else echo "n"; fi
}

gitcleanup() {
  ignore=${1:-master}
  git fetch --prune
  git checkout $ignore
  git add .
  git stash
  git pull --rebase
  git branch | grep -v "master" | xargs git branch -D
}

gitrebase() {
  [ -n "$1" ] && git pull --rebase origin $1
}

git-merge-to() {
  PUSH=false
  for p in "$@"; do
    case "$p" in
      --push) PUSH=true; break; ;;
    esac
  done

  target=$1
  current=$(git branch --show-current)
  git checkout $target
  git merge $current
  if [[ $PUSH=="true" ]]; then
    git push
  fi
  git checkout $current
}

git-retag() {
  tag=$1
  git tag -d $tag
  git push --delete origin $tag
  git tag $tag ${@:2}
  git push --tags
}

git-rebranch() {
  branch=$1
  current=$(git rev-parse --abbrev-ref HEAD | xargs | tr -d '\n')
  if [[ $branch == $current ]]; then
    echo "The target branch is the same as the current branch. Not doing anything"
    return 0
  fi
  
  if [[ -n $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep '^'$branch'$') ]]; then
    echo "Deleting branch $branch"
    git branch -D $branch
  fi

  git checkout -b $branch
  git push -f
  git checkout $current
}

_gitrebase_completion() {
  local remotes=`git branch -r | awk -F "origin/" '{print $2}'`
  COMPREPLY=($(compgen -W "$remotes"))
  return 0
} && complete -F _gitrebase_completion gitrebase git-merge-to
