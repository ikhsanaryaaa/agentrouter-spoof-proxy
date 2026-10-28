#!/usr/bin/env bash
# ar-diag.sh — diagnose AgentRouter Spoof Proxy <-> 9Router 401s.
# Usage: ./ar-diag.sh [PROXY_BASE_URL]
#   ./ar-diag.sh                       # default http://localhost:8318
#   ./ar-diag.sh http://agentrouter-proxy:8318   # from inside 9Router's network
#
# Exits 0 when every check passes, 1 otherwise. Never prints secret values.
set -uo pipefail

BASE="${1:-http://localhost:8318}"
BASE="${BASE%/}"
FAIL=0

c_ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
c_bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=1; }
c_warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }
hdr()    { printf '\n%s\n' "$1"; }

code() { curl -s -m 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || echo 000; }
body() { curl -s -m 15 "$@" 2>/dev/null; }

hdr "1. Reachability — $BASE"
H_BODY=$(body "$BASE/health")
H_CODE=$(code "$BASE/health")
if [ "$H_CODE" = "200" ]; then
  c_ok "GET /health -> 200"
  echo "        $H_BODY"
else
  c_bad "GET /health -> $H_CODE  (proxy down, wrong URL, or wrong port)"
  echo "        Fix: 9Router on another Docker network must use the container"
  echo "        name (http://agentrouter-proxy:8318) or the host LAN IP."
  echo "        Inside Docker, 'localhost' is the container itself, not the host."
  exit 1
fi

case "$H_BODY" in
  *'"wafCookie":true'*)  c_ok "WAF cookie present" ;;
  *) c_warn "wafCookie false — warmup still running, wait 5s and retry" ;;
esac
case "$H_BODY" in
  *'"circuitOpen":false'*) c_ok "circuit breaker closed" ;;
  *) c_warn "circuitOpen true — upstream failing, wait for backoff" ;;
esac

hdr "2. Model list — GET /v1/models (used by 'Import from /models')"
M_CODE=$(code "$BASE/v1/models")
M_BODY=$(body "$BASE/v1/models")
if [ "$M_CODE" = "200" ]; then
  N=$(printf '%s' "$M_BODY" | grep -o '"id"' | wc -l | tr -d ' ')
  c_ok "GET /v1/models -> 200 ($N models)"
  printf '%s' "$M_BODY" | tr ',' '\n' | grep -o '"id":"[^"]*"' | sed 's/"id":"/        - /; s/"$//' | head -12
else
  c_bad "GET /v1/models -> $M_CODE"
fi

hdr "3. Auth gate — is PROXY_AUTH_TOKEN set on the proxy?"
# /v1/models is always open; a proxied route without a token reveals the gate.
P_CODE=$(code -X POST "$BASE/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"x","messages":[{"role":"user","content":"y"}]}')
GATE=unknown
if [ "$P_CODE" = "401" ]; then
  NOAUTH_BODY=$(body -X POST "$BASE/v1/chat/completions" -H 'Content-Type: application/json' \
    -d '{"model":"x","messages":[{"role":"user","content":"y"}]}')
  case "$NOAUTH_BODY" in
    *"proxy auth token"*)
      GATE=on
      c_ok "gate is ON (PROXY_AUTH_TOKEN set) — 9Router MUST send it"
      echo "        --> 9Router provider 'API Key' must equal PROXY_AUTH_TOKEN."
      echo "        --> And UPSTREAM_API_KEY must hold the real agentrouter.org key,"
      echo "            otherwise upstream replies 401 new_api_error (无效的令牌)."
      ;;
    *"new_api_error"*)
      GATE=off
      c_ok "gate is OFF (no PROXY_AUTH_TOKEN) — client token goes straight upstream"
      echo "        --> 9Router provider 'API Key' must be the real agentrouter.org key."
      ;;
    *) c_warn "401 with unexpected body: $NOAUTH_BODY" ;;
  esac
else
  c_warn "unauthenticated POST -> $P_CODE (gate may be off and upstream answered)"
fi

hdr "4. Verdict"
if [ "$FAIL" = "0" ]; then
  printf '  \033[32mProxy is healthy and reachable.\033[0m\n'
  cat <<'TXT'

  Remaining 401 sources, in order of likelihood:
   A. 9Router 'API Key' != PROXY_AUTH_TOKEN  ->  "Invalid or missing proxy auth token"
   B. API Key == gate but UPSTREAM_API_KEY empty ->  "无效的令牌 / new_api_error"
      (the gate token was forwarded to agentrouter.org, which rejects it)
   C. Key pasted with a trailing space/newline or a truncated fragment.
   D. 9Router model-lock still active. The "(reset after 2m)" in the log is
      9Router backing off; the key must be fixed AND 2 minutes waited.
TXT
  exit 0
fi
printf '  \033[31mProxy reachable but checks failed — see FAIL lines above.\033[0m\n'
exit 1
