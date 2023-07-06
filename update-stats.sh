#!/usr/bin/env bash

set -e

main () {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)
        FORCE=1
        shift
        ;;
      -p|--publish)
        PUBLISH=1
        shift
        ;;
      *)
        echo "unknown flag: '$1'"
        exit 1
        ;;
    esac
  done

  # prompt for GITHUB_TOKEN if unset
  GITHUB_TOKEN=
  if [ -z "$GITHUB_TOKEN" ]; then
    read -p "GITHUB_TOKEN: " -s GITHUB_TOKEN
    echo
    export GITHUB_TOKEN
  fi

  # if README.md is dirty, exit or discard changes if --force is used
  if ! git diff --quiet README.md; then
    if [ -n "$FORCE" ]; then
      echo "README.md has changes; forcing discard"
      git checkout README.md
    else
      echo "README.md has changes; abort"
      exit 1
    fi
  fi

  echo "generating stats in README.md"
	gh-stats all --template templates/README.md.tmpl --template-extras templates/README-extras.json --output README.md

  if git diff --quiet README.md; then
    echo "no new stats calculated; README.md unchanged"
    return
  fi

  echo "README.md updated"
  [ -n "$PUBLISH" ] || return

  git add README.md
  git commit -m 'Update stats'
  git push
}

main "$@"
