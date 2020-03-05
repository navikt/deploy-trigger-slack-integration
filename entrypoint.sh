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
  [ "$GITHUB_REF" = "refs/heads/master" ] && INPUT_ALLOW_PROD='true' || INPUT_ALLOW_PROD='false'
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
# Overridden by INPUT_COMMIT_BRANCH if set
if [[ ! -z "$INPUT_COMMIT_BRANCH" ]]; then
  SHORT_REF=$INPUT_COMMIT_BRANCH
elif [[ -z "$GITHUB_HEAD_REF" ]]; then
  SHORT_REF=${GITHUB_REF//refs\/heads\//}
else
  SHORT_REF=$GITHUB_HEAD_REF
fi


# Naively infer preprod environments unless explicitly specified. Only likely to work for dittnav apps due to assumptions about file structure.
if [[ ! -z $INPUT_PREPROD_ENVIRONMENTS ]]; then
  PREPROD_ENVIRONMENTS=$INPUT_PREPROD_ENVIRONMENTS
else
  PREPROD_ENVIRONMENTS=$(find ./nais/dev-sbs -type f -name "*.json" | sed 's/.\/nais\/dev-sbs\///g' | sed 's/.json//g' | sort)
fi


# Add link buttons for slack message
BUTTONS=()

for dev_env in ${PREPROD_ENVIRONMENTS}; do
  BUTTONS+=($(createDevButton $dev_env))
done

# Add prod-button if allowed and config folder for prod-sbs exists
if [[ $INPUT_ALLOW_PROD == 'true' ]]; then
  if [[ -d nais/prod-sbs ]]; then
    BUTTONS+=($(createProdButton))
  fi
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