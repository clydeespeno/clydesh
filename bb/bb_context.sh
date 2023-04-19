#!/usr/bin/env bash

# if there are 2 params, add a new context, 1st param is the alias, 2nd and 3rd is team and repository. Repository is optional
if [[ "$#" -ge "2" ]]; then
  echo "Adding context $1"
  echo "$2 $3" > "${CLYDESH_HOME}/.alias/bb/$1"
  # set context if no current context is added yet
  if [[ ! -f "${CLYDESH_HOME}/.alias/bb/.current" ]]; then
    echo "No existing context found"
    "${CLYDESH_HOME}"/bb/bb_context.sh "$1"
  else
    echo "run the following to set the context to this alias"
    echo "  bb use $1"
  fi
elif [[ "$#" -eq "1" ]]; then
  echo "Using context $1."
  echo "$1"
else
  cat "${CLYDESH_HOME}/.alias/bb/.current"
fi