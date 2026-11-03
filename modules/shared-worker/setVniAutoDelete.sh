#!/bin/bash
### Sets auto_delete=true on a virtual network interface that is already attached to a VSI,
### so IBM Cloud deletes the VNI automatically when the VSI is deleted (also from the console or CLI).
### IBM Cloud only accepts auto_delete=true on a VNI that is bound to a target, so it cannot be set at creation time
### of a standalone VNI. Terraform creates the VNI with auto_delete=false, attaches it, and then runs this script.
###
### Environment variable required: IBMCLOUD_API_KEY (provided by the shell provider)
### Usage: ./setVniAutoDelete.sh <REGION> <VNI_ID>
### Only the final JSON line goes to stdout (the shell provider parses it); everything else goes to stderr.

set -euo pipefail

REGION="$1"
VNI_ID="$2"
API_VERSION="2024-06-01"

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

## Get IAM token
ACCESS_TOKEN="$(curl -sS -X POST "https://iam.cloud.ibm.com/identity/token" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=urn:ibm:params:oauth:grant-type:apikey' \
  --data-urlencode "apikey=${IBMCLOUD_API_KEY}" | jq -r '.access_token')"

if [ -z "${ACCESS_TOKEN}" ] || [ "${ACCESS_TOKEN}" = "null" ]; then
  echo "Could not get an IAM token (check IBMCLOUD_API_KEY)" >&2
  exit 1
fi

## Set auto_delete=true on the attached VNI
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X PATCH \
  "https://${REGION}.iaas.cloud.ibm.com/v1/virtual_network_interfaces/${VNI_ID}?version=${API_VERSION}&generation=2" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'Content-Type: application/merge-patch+json' \
  -d '{"auto_delete": true}')"

if [ "${HTTP_CODE}" != "200" ]; then
  echo "PATCH virtual_network_interfaces/${VNI_ID} failed with HTTP ${HTTP_CODE}:" >&2
  cat "$RESPONSE_FILE" >&2
  exit 1
fi

AUTO_DELETE="$(jq -r '.auto_delete' "$RESPONSE_FILE")"
echo "VNI ${VNI_ID}: auto_delete=${AUTO_DELETE}" >&2

if [ "${AUTO_DELETE}" != "true" ]; then
  echo "IBM Cloud did not apply auto_delete=true on ${VNI_ID}" >&2
  exit 1
fi

echo "{\"vni_id\": \"${VNI_ID}\", \"auto_delete\": \"${AUTO_DELETE}\"}"
