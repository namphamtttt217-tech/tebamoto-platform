#!/usr/bin/env bash
set -eu
python3 - <<'EOF'
import json, os, urllib.parse, urllib.request

idtoken = urllib.request.Request(
    os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=api://AzureADTokenExchange",
    headers={"Authorization": "bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
assertion = json.load(urllib.request.urlopen(idtoken))["value"]

body = urllib.parse.urlencode({
    "grant_type": "client_credentials",
    "client_id": os.environ["AZURE_CLIENT_ID"],
    "scope": "https://vault.azure.net/.default",
    "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    "client_assertion": assertion,
}).encode()

url = f"https://login.microsoftonline.com/{os.environ['AZURE_TENANT_ID']}/oauth2/v2.0/token"
print(json.load(urllib.request.urlopen(urllib.request.Request(url, body)))["access_token"])
EOF
