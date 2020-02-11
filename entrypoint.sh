#!/bin/bash

createDevButton() {
  echo $( jq -n -c \
          --arg txt $(printf '%s\n' "$1" | awk '{print toupper($0) }') \
          --arg url "$INPUT_DEPLOY_PROXY_URL/deploy/dev/$REPOSITORY_PARAM/$INPUT_COMMIT_SHA/$1" \
          '{ type: "button", text: { type: "plain_text", text: $txt }, url: $url }' \
  )
}

createProdButton() {
  echo $( jq -n -c \
          --arg url "$INPUT_DEPLOY_PROXY_URL/deploy/prod/$REPOSITORY_PARAM/$INPUT_COMMIT_SHA" \
          '{ type: "button", text: { type: "plain_text", text: "Prod" }, url: $url, style: "danger" }' \
  )
}

toArray() {
  local IFS=","; echo "[$*]"
}


# Show prod-deploy button only for master branch by default. Can be overridden by setting INPUT_ALLOW_PROD
if [[ -z "$INPUT_ALLOW_PROD" ]]; then
  [ "$GITHUB_REF" = "refs/heads/master" ] && INPUT_ALLOW_PROD=true || INPUT_ALLOW_PROD=false
fi

# Use provided commit sha if specified
if [[ -z "$INPUT_COMMIT_SHA" ]]; then
  INPUT_COMMIT_SHA=$GITHUB_SHA
fi

# Convenience variables
REPOSITORY_PARAM=$(echo $GITHUB_REPOSITORY | sed 's/\//%2F/g')
SHORT_SHA=$(echo $INPUT_COMMIT_SHA | cut -c1-7)
SHORT_REPO=$(echo $GITHUB_REPOSITORY | rev | cut -f1 -d"/" | rev )

# Find branch name in pretty format (remove 'refs/heads' on normal branches. Use provided GITHUB_HEAD_REF on temporary branches)
if [[ -z "$GITHUB_HEAD_REF" ]]; then
  SHORT_REF=${GITHUB_REF//refs\/heads\//}
else
  SHORT_REF=$GITHUB_HEAD_REF
fi


# Add link buttons for slack message
BUTTONS=()

for dev_env in ${INPUT_PREPROD_ENVIRONMENTS}; do
  BUTTONS+=($(createDevButton $dev_env))
done

if $INPUT_ALLOW_PROD; then
  BUTTONS+=($(createProdButton))
fi


# Create slack message payload
SLACK_PAYLOAD_BASE=$(jq -n -c \
                    --arg chn "$INPUT_SLACK_CHANNEL" \
                    --arg usr "GH Actions Deploy - $SHORT_REPO" \
                    --arg msg "Deploy \`$SHORT_REF  $SHORT_SHA\`" \
                    '{ channel: $chn, username: $usr, text: "Deploy-knapp", icon_emoji: ":git:", blocks: [ { type: "section", text: { type: "mrkdwn", text: $msg } },  { type: "actions", elements: [] } ] }' )

SLACK_PAYLOAD=$(echo $SLACK_PAYLOAD_BASE | jq -c '.blocks[1].elements = '"$(toArray ${BUTTONS[@]})")


# Post message to slack webook endpoint
curl -X POST --data-urlencode "payload=$SLACK_PAYLOAD" $INPUT_WEBHOOK_URL