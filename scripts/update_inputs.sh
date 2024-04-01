#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix -p jq -p git -p tea -p yq-go
set -e

tea logins add --url https://gitea.hillion.co.uk --token $GITEA_SERVER_TOKEN

INIT_HASH=$(git rev-parse HEAD) 
PULLS=$(tea pulls list --output yaml | grep -v NOTE)

git remote -v

INPUTS=$(nix flake metadata --json | jq '.locks.nodes | keys | .[]' -r)
for input in $INPUTS; do
  echo "Starting update for: $input"

  git switch --detach $INIT_HASH

  BRANCH=updater/$input
  PULL_INDEX=$(echo "$PULLS" | yq ".[] | select( .head == \"$BRANCH\" ) | .index")

  nix flake lock --update-input $input
  if git diff --exit-code; then
    if ! [ -z $PULL_INDEX ]; then
      tea pulls close $PULL_INDEX
      tea pulls clean $PULL_INDEX
    fi
    continue
  fi

  git switch --force-create updater/$input

  LAST_MODIFIED=$(nix flake metadata --json | jq ".locks.nodes.\"$input\".locked.lastModified")
  git commit --date="$LAST_MODIFIED" -am "updater: update $input"
  git push --set-upstream --force origin updater/$input

  
  exit 1
done

git switch --detach $INIT_HASH

