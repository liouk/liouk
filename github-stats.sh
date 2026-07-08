#!/usr/bin/env bash

set -e

USER="liouk"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRAS="${SCRIPT_DIR}/templates/README-extras.json"
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

  fetch_stats
  generate_readme
  sed -e '/^<!--/,/-->/d' -e 's/<[^>]*>//g' "$OUTPUT"

  if [ -z "$FORCE" ]; then
    if git diff --quiet README.md; then
      return
    fi
  fi
  [ -n "$PUBLISH" ] || return

  git config user.name "github-actions"
  git config user.email "noreply@github.com"
  git add README.md
  git commit -m 'Update stats'
  git push
}

fetch_stats() {
  NUM_REPOS=$(gh api graphql \
    -f query='{
      user(login:"'"$USER"'") {
        repositories(ownerAffiliations:OWNER, isFork:false, privacy:PUBLIC) { totalCount }
      }
    }' -q '.data.user.repositories.totalCount')

  NUM_FORKS=$(gh api graphql \
    -f query='{
      user(login:"'"$USER"'") {
        repositories(ownerAffiliations:OWNER, isFork:true, privacy:PUBLIC) { totalCount }
      }
    }' -q '.data.user.repositories.totalCount')

  NUM_OPEN_PULLS=$(gh api "search/issues?q=is:public+author:${USER}+type:pr+is:open" \
    -q '.total_count')

  NUM_MERGED_PULLS=$(gh api "search/issues?q=is:public+author:${USER}+type:pr+is:merged" \
    -q '.total_count')

  NUM_PULLS=$(gh api "search/issues?q=is:public+author:${USER}+type:pr" \
    -q '.total_count')

  NUM_CLOSED_PULLS=$((NUM_PULLS - NUM_OPEN_PULLS - NUM_MERGED_PULLS))

  NUM_COMMITS=$(gh api "search/commits?q=author:${USER}+is:public" \
    -q '.total_count')

  NUM_REVIEWS=$(gh api "search/issues?q=is:public+type:pr+assignee:${USER}" \
    -q '.total_count')

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

stat_line() {
  local name="$1" url="$2" value="$3"
  local ndots=$((18 - ${#name} - ${#value}))
  [ "$ndots" -lt 3 ] && ndots=3
  local dots=$(printf '%*s' "$ndots" '' | tr ' ' '.')
  printf '  ┃   * <a href="%s">%s</a> %s %s\n' "$url" "$name" "$dots" "$value"
}

lang_line() {
  local name="$1" url="$2" perc="$3"
  local name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

  local pad_count=$((8 - ${#name_lower}))
  [ "$pad_count" -lt 1 ] && pad_count=1
  local namepad=$(printf '%*s' "$pad_count" '')

  local bar_width=21
  local filled=$(awk "BEGIN {v=int($perc / 100 * $bar_width + 0.5); if(v<1)v=1; if(v>$bar_width)v=$bar_width; print v}")
  local empty_count=$((bar_width - filled))

  local bar=""
  local i
  for ((i=0; i<filled; i++)); do bar+="■"; done
  for ((i=0; i<empty_count; i++)); do bar+="·"; done

  local perc_fmt=$(printf '%5.2f%%' "$perc")
  printf '  ┃   <a href="%s">%s</a>%s [%s]  %s\n' "$url" "$name_lower" "$namepad" "$bar" "$perc_fmt"
}

generate_readme() {

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

  {
    cat <<'HEADER'
<!--
  Generated with github-stats.sh
-->

HEADER

    echo '<pre>'
    echo
    printf '  %s@github:~$ whoami\n' "$USER"
    echo
    echo '  ┃   senior engineer @ <a href="https://www.redhat.com">Red Hat</a> · <a href="https://www.redhat.com/en/technologies/cloud-computing/openshift">OpenShift</a> Control Plane'
    echo
    printf '  %s@github:~$ ./github-stats.sh\n' "$USER"
    echo

    stat_line "repos" \
      "https://github.com/${USER}?tab=repositories&q=&type=source&language=&sort=" \
      "$NUM_REPOS"
    stat_line "forks" \
      "https://github.com/${USER}?tab=repositories&q=&type=fork&language=&sort=" \
      "$NUM_FORKS"
    local pr_search="https://github.com/search?q=is%3Apublic+author%3A${USER}+type%3Apr"
    local ndots=$((18 - 5 - ${#NUM_PULLS}))
    [ "$ndots" -lt 3 ] && ndots=3
    local dots=$(printf '%*s' "$ndots" '' | tr ' ' '.')
    printf '  ┃   * <a href="%s&type=Issues">pulls</a> %s %s (<a href="%s+is%%3Aopen">%s open</a> / <a href="%s+is%%3Aclosed+is%%3Aunmerged">%s closed</a> / <a href="%s+is%%3Amerged">%s merged</a>)\n' \
      "$pr_search" "$dots" "$NUM_PULLS" \
      "$pr_search" "$NUM_OPEN_PULLS" \
      "$pr_search" "$NUM_CLOSED_PULLS" \
      "$pr_search" "$NUM_MERGED_PULLS"
    stat_line "commits" \
      "https://github.com/search?q=author%3A${USER}+is%3Apublic+&type=commits&s=author-date&o=desc" \
      "$NUM_COMMITS"
    stat_line "reviews" \
      "https://github.com/search?q=is%3Apublic+type%3Apr+assignee%3A${USER}&type=issues" \
      "$NUM_REVIEWS"

    echo '  ┃'

    while IFS=$'\t' read -r name perc; do
      local color
      color=$(jq -r ".langColors[\"${name}\"] // empty" "$EXTRAS")
      [ -z "$color" ] && continue
      lang_line "$name" \
        "https://github.com/search?q=is%3Apublic+user%3A${USER}+language%3A${name}&type=repositories" \
        "$perc"
    done <<< "$lang_lines"

    echo
    printf '  %s@github:~$ ./interests.sh\n' "$USER"
    echo
    echo '  ┃   go · shell · git · dev tooling · agentic SDLC'
    echo '  ┃   kubernetes · openshift · linux · docker · cloud native'
    echo '  ┃   open source · software/web security'
    echo
    echo '</pre>'
  } > "$OUTPUT"
}

main "$@"
