#!/usr/bin/env bash

set -e

USER="liouk"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRAS="${SCRIPT_DIR}/templates/README-extras.json"
TEMPLATE="${SCRIPT_DIR}/templates/README.md.tmpl"
OUTPUT="${SCRIPT_DIR}/README.md"

main() {
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

  if [ -z "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN is not set"
    exit 1
  fi

  if ! git diff --quiet README.md 2>/dev/null; then
    echo "README.md has changes; abort"
    exit 1
  fi

  fetch_stats
  generate_readme

  if [ -z "$FORCE" ]; then
    if git diff --quiet README.md; then
      echo "no new stats calculated; README.md unchanged"
      return
    fi
  fi

  local num=$(/bin/ls -1 "${SCRIPT_DIR}/assets/liouk-logos" | wc -l)
  local liouk_logo="liouk-$(( RANDOM % num )).png"
  sed -i "s/liouk.png/${liouk_logo}/" "$OUTPUT"

  echo "README.md updated"
  [ -n "$PUBLISH" ] || return

  git add README.md
  git commit -m 'Update stats'
  git push
}

fetch_stats() {
  echo "fetching repo stats..."
  export NUM_REPOS=$(gh api graphql \
    -f query='{
      user(login:"'"$USER"'") {
        repositories(ownerAffiliations:OWNER, isFork:false, privacy:PUBLIC) { totalCount }
      }
    }' -q '.data.user.repositories.totalCount')

  export NUM_FORKS=$(gh api graphql \
    -f query='{
      user(login:"'"$USER"'") {
        repositories(ownerAffiliations:OWNER, isFork:true, privacy:PUBLIC) { totalCount }
      }
    }' -q '.data.user.repositories.totalCount')

  echo "fetching PR stats..."
  export NUM_OPEN_PULLS=$(gh api "search/issues?q=is:public+author:${USER}+type:pr+is:open" \
    -q '.total_count')

  export NUM_MERGED_PULLS=$(gh api "search/issues?q=is:public+author:${USER}+type:pr+is:merged" \
    -q '.total_count')

  export NUM_PULLS=$(gh api "search/issues?q=is:public+author:${USER}+type:pr" \
    -q '.total_count')

  export NUM_CLOSED_PULLS=$((NUM_PULLS - NUM_OPEN_PULLS - NUM_MERGED_PULLS))

  echo "fetching commit stats..."
  export NUM_COMMITS=$(gh api "search/commits?q=author:${USER}+is:public" \
    -q '.total_count')

  echo "fetching review stats..."
  export NUM_REVIEWS=$(gh api "search/issues?q=is:public+type:pr+assignee:${USER}" \
    -q '.total_count')

  echo "fetching language stats..."
  LANG_DATA=$(gh api graphql -f query='{
    user(login:"'"$USER"'") {
      repositories(ownerAffiliations:OWNER, isFork:false, privacy:PUBLIC, first:100) {
        nodes {
          languages(first:20) {
            edges {
              size
              node { name }
            }
          }
        }
      }
    }
  }')
}

generate_readme() {
  echo "generating README.md..."

  export REPO_LOGO=$(jq -r '.repoLogo' "$EXTRAS")
  export FORK_LOGO=$(jq -r '.forkLogo' "$EXTRAS")
  export PULL_LOGO=$(jq -r '.pullLogo' "$EXTRAS")
  export COMMIT_LOGO=$(jq -r '.commitLogo' "$EXTRAS")
  export REVIEW_LOGO=$(jq -r '.reviewLogo' "$EXTRAS")
  export USER

  local lang_lines
  lang_lines=$(echo "$LANG_DATA" | jq -r '
    [.data.user.repositories.nodes[].languages.edges[] | {name: .node.name, size: .size}]
    | group_by(.name)
    | map({name: .[0].name, total: (map(.size) | add)})
    | sort_by(-.total)
    | . as $all
    | ($all | map(.total) | add) as $sum
    | $all[]
    | "\(.name)\t\(.total / $sum * 100)"
  ')

  local lang_html=""
  while IFS=$'\t' read -r name perc; do
    local color logo perc_fmt
    color=$(jq -r ".langColors[\"${name}\"] // empty" "$EXTRAS")
    logo=$(jq -r ".langLogos[\"${name}\"] // empty" "$EXTRAS")
    [ -z "$color" ] && continue
    perc_fmt=$(printf "%.2f" "$perc")
    lang_html+="<a href=\"https://github.com/search?q=is%3Apublic+user%3A${USER}+language%3A${name}&type=repositories\">
<img title=\"${name}\" src=\"https://img.shields.io/static/v1?label=&message=${perc_fmt}%&labelColor=${color}&color=grey&style=flat-square&logo=${logo}\">
</a>
<br />
"
  done <<< "$lang_lines"

  export LANGUAGES="$lang_html"

  envsubst '$USER $NUM_REPOS $NUM_FORKS $NUM_OPEN_PULLS $NUM_CLOSED_PULLS $NUM_MERGED_PULLS $NUM_PULLS $NUM_COMMITS $NUM_REVIEWS $REPO_LOGO $FORK_LOGO $PULL_LOGO $COMMIT_LOGO $REVIEW_LOGO $LANGUAGES' \
    < "$TEMPLATE" > "$OUTPUT"
}

main "$@"
