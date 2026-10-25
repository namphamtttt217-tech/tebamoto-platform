#!/usr/bin/env bash
set -eu
python3 - <<'EOF'
import base64, json, os, urllib.parse, urllib.request

# 1) runner xin OIDC token cua GitHub (audience = AzureADTokenExchange)
req = urllib.request.Request(
    os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=api://AzureADTokenExchange",
    headers={"Authorization": "bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
assertion = json.load(urllib.request.urlopen(req))["value"]

# 2) giai JWT (khong verify, chi doc payload) — cac claim quyet dinh Azure co nhan hay khong
payload = assertion.split(".")[1]
payload += "=" * (-len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload))
for k in ("iss", "aud", "sub", "repository", "event_name"):
    print(f"{k:12} {claims.get(k)}")

# 3) doi assertion lay token Azure AD theo dang vai tbl-cicd-deployer
body = urllib.parse.urlencode({
    "grant_type": "client_credentials",
    "client_id": os.environ["AZURE_CLIENT_ID"],
    "scope": "https://vault.azure.net/.default",
    "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    "client_assertion": assertion,
}).encode()
url = f"https://login.microsoftonline.com/{os.environ['AZURE_TENANT_ID']}/oauth2/v2.0/token"
tok = json.load(urllib.request.urlopen(urllib.request.Request(url, body)))["access_token"]
print(f"azure_token  {tok[:40]}... (len={len(tok)})")
