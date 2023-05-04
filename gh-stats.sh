#!/usr/bin/env bash

num_repos=$(gh search repos --owner liouk is:public --json fullName | jq '. | length')
num_forks=$(gh search repos --owner liouk is:public --include-forks only --json fullName | jq '. | length')
num_prs=$(gh search prs --author liouk --visibility public --json id | jq '. | length')
num_commits=$(gh search commits --author liouk --visibility public --order asc --sort author-date --limit 1000 --json sha | jq '. | length')

sed -i "s/label=Repos\&message=[[:digit:]]\+/label=Repos\&message=$num_repos/g" README.md
sed -i "s/label=Forks\&message=[[:digit:]]\+/label=Forks\&message=$num_forks/g" README.md
sed -i "s/label=PRs\&message=[[:digit:]]\+/label=PRs\&message=$num_prs/g" README.md
sed -i "s/label=Commits\&message=[[:digit:]]\+/label=Commits\&message=$num_commits/g" README.md
