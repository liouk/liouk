.PHONY:stats
stats:
	gh-stats all --template templates/README.md.tmpl --template-extras templates/README-extras.json --output README.md
