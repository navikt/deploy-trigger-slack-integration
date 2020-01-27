#!/bin/bash

createDevButton() {
  echo $( jq -n -c \
          --arg txt $(printf '%s\n' "$1" | awk '{print toupper($0) }') \
          --arg url "$INPUT_DEPLOY_PROXY_URL/deploy/dev/$REPOSITORY_PARAM/$GITHUB_SHA/$1" \
          '{ type: "button", text: { type: "plain_text", text: $txt }, url: $url }' \
  )
}

createProdButton() {
  echo $( jq -n -c \
          --arg url "$INPUT_DEPLOY_PROXY_URL/deploy/prod/$REPOSITORY_PARAM/$GITHUB_SHA" \
          '{ type: "button", text: { type: "plain_text", text: "Prod" }, url: $url, style: "danger" }' \
  )
}

toArray() {
  local IFS=","; echo "[$*]"
}


# Show prod-deploy button only for master branch by default. Can be overridden by setting INPUT_ALLOW_PROD
if [[ -z "$INPUT_ALLOW_PROD" ]]; then
  [ "$GITHUB_REF" = "master" ] && INPUT_ALLOW_PROD=true || INPUT_ALLOW_PROD=false
fi

# Convenience variables
REPOSITORY_PARAM=$(echo $GITHUB_REPOSITORY | sed 's/\//%2F/g')
SHORT_SHA=$(echo $GITHUB_SHA | cut -c1-7)
SHORT_REPO=$(echo $GITHUB_REPOSITORY | rev | cut -f1 -d"/" | rev )


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
                    --arg msg "Deploy commit \`$SHORT_SHA\`" \
                    '{ channel: $chn, username: $usr, text: "Deploy-knapp", icon_emoji: ":git:", blocks: [ { type: "section", text: { type: "mrkdwn", text: $msg } },  { type: "actions", elements: [] } ] }' )

SLACK_PAYLOAD=$(echo $SLACK_PAYLOAD_BASE | jq -c '.blocks[1].elements = '"$(toArray ${BUTTONS[@]})")


# Post message to slack webook endpoint
curl -X POST --data-urlencode "payload=$SLACK_PAYLOAD" $INPUT_WEBHOOK_URL