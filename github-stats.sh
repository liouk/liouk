#!/usr/bin/env bash

set -e

USER="liouk"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRAS="${SCRIPT_DIR}/templates/README-extras.json"
OUTPUT="${SCRIPT_DIR}/README.md"
CARD_OUTPUT="${SCRIPT_DIR}/docs/index.html"

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
  generate_card
  sed -e '/^<!--/,/-->/d' -e 's/<[^>]*>//g' "$OUTPUT"

  if [ -z "$FORCE" ]; then
    if git diff --quiet README.md; then
      return
    fi
  fi
  [ -n "$PUBLISH" ] || return

  git add docs/index.html
  git config user.name "github-actions"
  git config user.email "1769158+liouk@users.noreply.github.com"
  git add README.md
  git commit -m 'Update stats'
  git push
}

fetch_stats() {
  FULL_NAME=$(gh api "users/${USER}" -q '.name')

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

card_stat_line() {
  local name="$1" url="$2" value="$3"
  local ndots=$((18 - ${#name} - ${#value}))
  [ "$ndots" -lt 3 ] && ndots=3
  local dots=$(printf '%*s' "$ndots" '' | tr ' ' '.')
  printf '<span class="bar">┃</span>   * <a href="%s">%s</a> <span class="muted">%s</span> <span class="stat-val">%s</span>\n' "$url" "$name" "$dots" "$value"
}

card_pulls_line() {
  local pr_search="https://github.com/search?q=is%3Apublic+author%3A${USER}+type%3Apr"
  local ndots=$((18 - 5 - ${#NUM_PULLS}))
  [ "$ndots" -lt 3 ] && ndots=3
  local dots=$(printf '%*s' "$ndots" '' | tr ' ' '.')
  printf '<span class="bar">┃</span>   * <a href="%s&type=Issues">pulls</a> <span class="muted">%s</span> <span class="stat-val">%s</span> (<a href="%s+is%%3Amerged">%s merged</a> / <a href="%s+is%%3Aopen">%s open</a> / <a href="%s+is%%3Aclosed+is%%3Aunmerged">%s closed</a>)\n' \
    "$pr_search" "$dots" "$NUM_PULLS" \
    "$pr_search" "$NUM_MERGED_PULLS" \
    "$pr_search" "$NUM_OPEN_PULLS" \
    "$pr_search" "$NUM_CLOSED_PULLS"
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
    echo '  ┃   email: <a href="mailto:hello@liouk.dev">hello@liouk.dev</a>'
    echo '  ┃   code:  <a href="https://github.com/liouk">github</a>'
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
    printf '  ┃   * <a href="%s&type=Issues">pulls</a> %s %s (<a href="%s+is%%3Amerged">%s merged</a> / <a href="%s+is%%3Aopen">%s open</a> / <a href="%s+is%%3Aclosed+is%%3Aunmerged">%s closed</a>)\n' \
      "$pr_search" "$dots" "$NUM_PULLS" \
      "$pr_search" "$NUM_MERGED_PULLS" \
      "$pr_search" "$NUM_OPEN_PULLS" \
      "$pr_search" "$NUM_CLOSED_PULLS"
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
    printf '  %s@github:~$ cat ~/about/interests.txt\n' "$USER"
    echo
    echo '  ┃   go · shell · git · dev tooling'
    echo '  ┃   linux · containers · kubernetes · cloud native'
    echo '  ┃   open source · software/web security · agentic SDLC'
    echo
    echo '</pre>'
  } > "$OUTPUT"
}

generate_card() {
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

  local lang_bars=""
  while IFS=$'\t' read -r name perc; do
    local color
    color=$(jq -r ".langColors[\"${name}\"] // empty" "$EXTRAS")
    [ -z "$color" ] && continue
    local name_lower
    name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    local url="https://github.com/search?q=is%3Apublic+user%3A${USER}+language%3A${name}&type=repositories"

    local bar_width=21
    local filled
    filled=$(awk "BEGIN {v=int($perc / 100 * $bar_width + 0.5); if(v<1)v=1; if(v>$bar_width)v=$bar_width; print v}")
    local empty_count=$((bar_width - filled))

    local filled_spans=""
    local i
    for ((i=0; i<filled; i++)); do filled_spans+="■"; done
    local empty_spans=""
    for ((i=0; i<empty_count; i++)); do empty_spans+="·"; done

    local pad_count=$((8 - ${#name_lower}))
    [ "$pad_count" -lt 1 ] && pad_count=1
    local namepad
    namepad=$(printf '%*s' "$pad_count" '')

    local perc_fmt
    perc_fmt=$(printf '%5.2f%%' "$perc")

    lang_bars+="<span class=\"bar\">┃</span>   <a href=\"${url}\">${name_lower}</a>${namepad}[<span style=\"color:#${color}\">${filled_spans}</span><span class=\"dot\">${empty_spans}</span>]  ${perc_fmt}
"
  done <<< "$lang_lines"

  cat > "$CARD_OUTPUT" <<CARD_EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>liouk</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0d0d1a;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 100vh;
    font-family: 'JetBrains Mono', monospace;
    padding: 20px;
  }
  .card {
    max-width: 680px;
    width: 100%;
  }
  .avatar {
    text-align: center;
    margin-bottom: 24px;
  }
  .avatar img {
    width: 120px;
    height: 120px;
    border-radius: 50%;
    border: 3px solid #ff79c6;
    box-shadow: 0 0 20px rgba(255, 121, 198, 0.3);
  }
  .name {
    color: #f8f8f2;
    font-size: 18px;
    margin-top: 12px;
    font-weight: 700;
  }
  .terminal {
    background: #0d0d1a;
    border: 2px solid #44475a;
    border-image: linear-gradient(90deg, #ff79c6, #bd93f9, #50fa7b) 1;
    overflow: hidden;
  }
  .content {
    padding: 24px;
    font-size: 14px;
    line-height: 1.4;
    color: #f8f8f2;
    white-space: pre;
    overflow-x: auto;
  }
  .prompt { color: #50fa7b; }
  .bar { color: #44475a; }
  .content a { color: #8be9fd; text-decoration: none; }
  .content a:hover { color: #ff79c6; text-decoration: underline; }
  .stat-val { color: #f8f8f2; }
  .muted { color: #6272a4; }
  @media (max-width: 500px) {
    .content { font-size: 11px; padding: 16px; }
    .avatar img { width: 80px; height: 80px; }
  }
</style>
</head>
<body>
<div class="card">
  <div class="avatar">
    <img src="https://github.com/${USER}.png" alt="${USER}">
    <div class="name">${FULL_NAME}</div>
  </div>
  <div class="terminal">
    <div class="content">
<span class="prompt">${USER}@liouk.dev:~\$</span> whoami

<span class="bar">┃</span>   senior engineer @ <a href="https://www.redhat.com">Red Hat</a> · <a href="https://www.redhat.com/en/technologies/cloud-computing/openshift">OpenShift</a> Control Plane
<span class="bar">┃</span>   email: <a href="mailto:hello@liouk.dev">hello@liouk.dev</a>
<span class="bar">┃</span>   code:  <a href="https://github.com/liouk">github</a>

<span class="prompt">${USER}@liouk.dev:~\$</span> ./github-stats.sh

$(card_stat_line "repos" "https://github.com/${USER}?tab=repositories&q=&type=source&language=&sort=" "$NUM_REPOS")
$(card_stat_line "forks" "https://github.com/${USER}?tab=repositories&q=&type=fork&language=&sort=" "$NUM_FORKS")
$(card_pulls_line)
$(card_stat_line "commits" "https://github.com/search?q=author%3A${USER}+is%3Apublic+&type=commits&s=author-date&o=desc" "$NUM_COMMITS")
$(card_stat_line "reviews" "https://github.com/search?q=is%3Apublic+type%3Apr+assignee%3A${USER}&type=issues" "$NUM_REVIEWS")
<span class="bar">┃</span>
${lang_bars}
<span class="prompt">${USER}@liouk.dev:~\$</span> cat ~/about/interests.txt

<span class="bar">┃</span>   go · shell · git · dev tooling
<span class="bar">┃</span>   linux · containers · kubernetes · cloud native
<span class="bar">┃</span>   open source · software/web security · agentic SDLC
</div>
  </div>
</div>
</body>
</html>
CARD_EOF
}

main "$@"
