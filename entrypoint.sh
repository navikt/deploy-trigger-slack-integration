#!/bin/bash

createDevButton() {
  CLUSTER="$1"
  NAMESPACE="$2"

  echo $( jq -n -c \
          --arg txt $(printf '%s\n' "$CLUSTER:$NAMESPACE" | awk '{print toupper($0) }') \
          --arg url "$INPUT_DEPLOY_PROXY_URL/deploy/ref/$REPOSITORY_PARAM/$INPUT_COMMIT_SHA/env/$CLUSTER/$NAMESPACE" \
          '{ type: "button", text: { type: "plain_text", text: $txt }, url: $url }' \
  )
}

createProdButton() {
  CLUSTER="$1"
  NAMESPACE="$2"

  echo $( jq -n -c \
          --arg txt $(printf '%s\n' "$CLUSTER:$NAMESPACE" | awk '{print toupper($0) }') \
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

# Add link buttons for slack message
BUTTONS=()


# Find all nais.yaml files for dev clusters in the nais folder
DEV_CONFIGS=$(find ./nais/dev-* -type f -name "*.yaml")

for nais_config in ${DEV_CONFIGS}; do
  # Determine cluster based on folder name
  DEV_CLUSTER=$(echo "$nais_config" | sed 's/.\/nais\///g' | sed 's/\/nais.yaml//g')

  # Read and extract namespace from the nais.yaml file
  DEV_ENVIRONMENT=$(grep -A4 'metadata:' "$nais_config" | grep 'namespace:' | sed 's/.*namespace: //' | xargs)

  # Create a button object for each given cluster-namespace combination
  BUTTONS+=($(createDevButton $DEV_CLUSTER $DEV_ENVIRONMENT))
done


# Add prod-button if allowed and config folder for prod exists
if [[ $INPUT_ALLOW_PROD == 'true' ]]; then
  PROD_CONFIGS=$(find ./nais/prod-* -type f -name "*.yaml")

  for nais_config in ${PROD_CONFIGS}; do
    PROD_CLUSTER=$(echo "$nais_config" | sed 's/.\/nais\///g' | sed 's/\/nais.yaml//g')

    PROD_ENVIRONMENT=$(grep -A4 'metadata:' "$nais_config" | grep 'namespace:' | sed 's/.*namespace: //' | xargs)

    BUTTONS+=($(createProdButton $PROD_CLUSTER $PROD_ENVIRONMENT))
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
