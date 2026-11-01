#!/bin/bash
### Environment variable required: IBMCLOUD_API_KEY
### Usage: ./getTFOutputs.sh <WORKSPACE_ID>

WORKSPACE_ID=$1
## Get IAM Token
ACCESS_TOKEN=`curl -X POST  "https://iam.cloud.ibm.com/identity/token?grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$IBMCLOUD_API_KEY" -H 'Accept: application/json' -H 'Content-Type: application/x-www-form-urlencoded'  | jq -r '.access_token'`

## Get Schematics workspace template_data ID
TEMPLATE_DATA_ID=`curl -X GET https://schematics.cloud.ibm.com/v1/workspaces/${WORKSPACE_ID} -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.template_data[0].id'`

## Get Schematics output variables
OUTPUT_DATA=`curl -X GET https://schematics.cloud.ibm.com/v1/workspaces/${WORKSPACE_ID}/output_values -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.[0].output_values'`

## Python call to organize in a nicer output
python3 formatOutput.py "${OUTPUT_DATA}"