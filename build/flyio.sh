#!/bin/bash

# Define the organization slug
ORG_SLUG="mayjuun"  # Replace this with your organization slug

# Define the application name
APP_NAME="pocketfhir"

# Path to your .env file
ENV_FILE="./config/.env.flyio"

# Launch the application with the specified organization
flyctl launch --name $APP_NAME --org $ORG_SLUG --region atl --no-deploy

# Read the .env file line by line
while IFS= read -r line || [ -n "$line" ]; do
  # Ignore empty lines and lines starting with #
  if [ -z "$line" ] || [ "${line:0:1}" == "#" ]; then
    continue
  fi
  # Set each secret
  flyctl secrets set $line --app $APP_NAME
done < "$ENV_FILE"

# Verify that the environment variables are set
flyctl secrets list --app $APP_NAME

# Deploy the application
flyctl deploy --app $APP_NAME --wait-timeout 300
