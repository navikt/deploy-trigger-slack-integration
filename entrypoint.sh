#!/bin/bash

createDevButton() {
  CLUSTER=$(echo $1 | sed 's/:.*//')
  NAMESPACE=$(echo $1 | sed 's/.*://')
  DISPLAY_NAMESPACE=""

  if [[ "$NAMESPACE" != "$INPUT_DEFAULT_NAMESPACE" ]]; then
    DISPLAY_NAMESPACE=":$NAMESPACE"
  fi

  echo $( jq -n -c \
          --arg txt $(printf '%s\n' "$CLUSTER$DISPLAY_NAMESPACE" | awk '{print toupper($0) }') \
          --arg url "$INPUT_DEPLOY_PROXY_URL/deploy/ref/$REPOSITORY_PARAM/$INPUT_COMMIT_SHA/env/$CLUSTER/$NAMESPACE" \
          '{ type: "button", text: { type: "plain_text", text: $txt }, url: $url }' \
  )
}

createProdButton() {
  CLUSTER=$(echo $1 | sed 's/:.*//')
  NAMESPACE=$(echo $1 | sed 's/.*://')
  DISPLAY_NAMESPACE=""

  if [[ "$NAMESPACE" != "$INPUT_DEFAULT_NAMESPACE" ]]; then
    DISPLAY_NAMESPACE=":$NAMESPACE"
  fi

  echo $( jq -n -c \
          --arg txt $(printf '%s\n' "$CLUSTER$DISPLAY_NAMESPACE" | awk '{print toupper($0) }') \
          --arg url "$INPUT_DEPLOY_PROXY_URL/deploy/ref/$REPOSITORY_PARAM/$INPUT_COMMIT_SHA/env/$CLUSTER/$NAMESPACE" \
          '{ type: "button", text: { type: "plain_text", text: $txt }, url: $url, style: "danger" }' \
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
  PREPROD_ENVIRONMENTS=$(find ./nais/dev-* -type f -name "*.json" | sed 's/.\/nais\///g' | sed 's/.json//g' | tr '/' ':' | sort)
fi


# Add link buttons for slack message
BUTTONS=()

for dev_env in ${PREPROD_ENVIRONMENTS}; do
  BUTTONS+=($(createDevButton $dev_env))
done

# Add prod-button if allowed and config folder for prod exists
if [[ $INPUT_ALLOW_PROD == 'true' ]]; then
  PROD_ENVIRONMENTS=$(find ./nais/prod-* -type f -name "*.json" | sed 's/.\/nais\///g' | sed 's/.json//g' | tr '/' ':' | sort)
  for prod_env in ${PROD_ENVIRONMENTS}; do
    BUTTONS+=($(createProdButton $prod_env))
  done
fi

# Set link to branch
if [[ $SHORT_REF == 'master' ]]; then
  BRANCH_LINK="https://github.com/$GITHUB_REPOSITORY"
else
  BRANCH_LINK="https://github.com/$GITHUB_REPOSITORY/tree/$SHORT_REF"
fi

# Set context message based on commit sha, branch name and commit message
if [[ -z $INPUT_COMMIT_MESSAGE ]]; then
  CONTEXT_MESSAGE="Deploy commit on branch *\`<$BRANCH_LINK|$SHORT_REF>\`* \n \`$SHORT_SHA\`"
else
  CONTEXT_MESSAGE="Deploy commit on branch *\`<$BRANCH_LINK|$SHORT_REF>\`* \n \`$SHORT_SHA\` - $INPUT_COMMIT_MESSAGE"
fi

# Create slack message payload
SLACK_PAYLOAD_BASE=$(jq -n -c \
                    --arg chn "$INPUT_SLACK_CHANNEL" \
                    --arg usr "GH Actions Deploy - $SHORT_REPO" \
                    --arg msg "$CONTEXT_MESSAGE" \
                    '{ channel: $chn, username: $usr, text: "Deploy-knapp", icon_emoji: ":git:", blocks: [ { type: "section", text: { type: "mrkdwn", text: $msg } },  { type: "actions", elements: [] } ] }' )

SLACK_PAYLOAD=$(echo $SLACK_PAYLOAD_BASE | jq -c '.blocks[1].elements = '"$(toArray ${BUTTONS[@]})")


# Bash, jq and curl seem to conspire to expand plaintext '\n' into '\\\\n'. This is rendered in slack as '\n', rather
# than a newline. The only workaround seems to be to replace '\\\\n' with '\\n'.
SLACK_PAYLOAD=$(echo $SLACK_PAYLOAD | sed 's/\\\\n/\\n/g')


# Post message to slack webook endpoint
curl -X POST --data-urlencode "payload=$SLACK_PAYLOAD" $INPUT_WEBHOOK_URL
