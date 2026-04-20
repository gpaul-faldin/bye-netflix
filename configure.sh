#!/usr/bin/env bash
# Auto-configures Radarr, Sonarr, Prowlarr and download clients via their APIs.
# Run once after ./start.sh on a fresh install.
# Safe to re-run — checks for existing config before adding anything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODO="${SCRIPT_DIR}/TODO.md"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

header() { echo -e "\n${CYAN}${BOLD}── $1 ──${RESET}"; }
ok()     { echo -e "${GREEN}✓ $1${RESET}"; }
warn()   { echo -e "${YELLOW}⚠ $1${RESET}"; }
fail()   { echo -e "${RED}✗ $1${RESET}"; }
skip()   { echo -e "  (skipped) $1"; }

# Mark a TODO.md line as done by its <!-- auto:tag --> marker
todo_done() {
  local tag="$1"
  if [[ -f "$TODO" ]]; then
    sed -i "s/- \[ \] \(.*<!-- auto:${tag} -->\)/- [x] \1/" "$TODO"
  fi
}

# ─── Load config ─────────────────────────────────────────────────────────────
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
  fail ".env not found — run ./setup.sh first"
  exit 1
fi
if [[ ! -f "${SCRIPT_DIR}/start.sh" ]]; then
  fail "start.sh not found — run ./setup.sh first"
  exit 1
fi

source "${SCRIPT_DIR}/.env"

# Detect which modules are active from start.sh
USE_TORRENT=false; USE_USENET=false; USE_VPN=false; USE_TRAKT=false
grep -q 'compose/torrent.yml' "${SCRIPT_DIR}/start.sh" && USE_TORRENT=true
grep -q 'compose/usenet.yml'  "${SCRIPT_DIR}/start.sh" && USE_USENET=true
grep -q 'compose/vpn.yml'     "${SCRIPT_DIR}/start.sh" && USE_VPN=true
grep -q 'compose/trakt.yml'   "${SCRIPT_DIR}/start.sh" && USE_TRAKT=true

COMPOSE_CMD=$(grep 'docker compose' "${SCRIPT_DIR}/start.sh" | head -1 | sed 's/ up -d.*//' | sed 's|cd.*; ||')

RADARR_BASE="http://localhost:7878"
SONARR_BASE="http://localhost:8989"
PROWLARR_BASE="http://localhost:9696"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║     Bye Netflix — Auto-Configure         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""

# ─── Helpers ─────────────────────────────────────────────────────────────────

wait_for_file() {
  local file="$1" label="$2" elapsed=0 max=120
  echo -n "  Waiting for ${label} config..."
  while [[ ! -f "$file" ]] && [[ $elapsed -lt $max ]]; do
    sleep 3; elapsed=$((elapsed+3)); echo -n "."
  done
  echo ""
  [[ -f "$file" ]]
}

wait_for_http() {
  local url="$1" key="$2" label="$3" elapsed=0 max=120
  echo -n "  Waiting for ${label}..."
  while [[ $elapsed -lt $max ]]; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Api-Key: $key" "$url" 2>/dev/null || true)
    if [[ "$code" == "200" ]]; then echo " ready"; return 0; fi
    sleep 3; elapsed=$((elapsed+3)); echo -n "."
  done
  echo " timed out"
  return 1
}

xml_key() { grep -oP "(?<=<ApiKey>)[^<]+" "$1" 2>/dev/null || true; }

arr_get()  { curl -s -H "X-Api-Key: $2" "$1"; }
# ?forceSave=true skips the live connection test — works for /downloadclient, not /applications
arr_post()      { curl -s -X POST -H "X-Api-Key: $2" -H "Content-Type: application/json" -d "$3" "${1}?forceSave=true"; }
arr_post_plain() { curl -s -X POST -H "X-Api-Key: $2" -H "Content-Type: application/json" -d "$3" "$1"; }

# Check if a name already exists in a JSON array response
already_exists() { echo "$1" | grep -q "\"name\":\"$2\""; }

# Probe which container URL Radarr can actually use to reach a service
probe_url_from_radarr() {
  local candidates=("$@")
  for url in "${candidates[@]}"; do
    if docker exec radarr wget --timeout=3 --tries=1 -qO/dev/null "$url" 2>/dev/null; then
      echo "$url"; return 0
    fi
  done
  echo ""
}

# ─── Step 1: Extract API keys ─────────────────────────────────────────────────
header "Extracting API keys from config files"

RADARR_XML="${SCRIPT_DIR}/config/radarr/config.xml"
SONARR_XML="${SCRIPT_DIR}/config/sonarr/config.xml"
PROWLARR_XML="${SCRIPT_DIR}/config/prowlarr/config.xml"

wait_for_file "$RADARR_XML"   "Radarr"   || { fail "Radarr config not found — is the stack running?"; exit 1; }
wait_for_file "$SONARR_XML"   "Sonarr"   || { fail "Sonarr config not found";  exit 1; }
wait_for_file "$PROWLARR_XML" "Prowlarr" || { fail "Prowlarr config not found"; exit 1; }

RADARR_KEY=$(xml_key "$RADARR_XML")
SONARR_KEY=$(xml_key "$SONARR_XML")
PROWLARR_KEY=$(xml_key "$PROWLARR_XML")

[[ -z "$RADARR_KEY"   ]] && { fail "Could not read Radarr API key";   exit 1; }
[[ -z "$SONARR_KEY"   ]] && { fail "Could not read Sonarr API key";   exit 1; }
[[ -z "$PROWLARR_KEY" ]] && { fail "Could not read Prowlarr API key"; exit 1; }

ok "Radarr   API key: ${RADARR_KEY:0:8}..."
ok "Sonarr   API key: ${SONARR_KEY:0:8}..."
ok "Prowlarr API key: ${PROWLARR_KEY:0:8}..."
todo_done "api-keys"

# ─── Step 2: Update .env ──────────────────────────────────────────────────────
header "Updating .env"

update_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "${SCRIPT_DIR}/.env"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "${SCRIPT_DIR}/.env"
  else
    echo "${key}=${val}" >> "${SCRIPT_DIR}/.env"
  fi
}

update_env "RADARR_API_KEY" "$RADARR_KEY"
update_env "SONARR_API_KEY" "$SONARR_KEY"

# Extract Tautulli API key for reference (used in scripts)
TAUTULLI_INI="${SCRIPT_DIR}/config/tautulli/config/config.ini"
if [[ -f "$TAUTULLI_INI" ]]; then
  TAUTULLI_KEY=$(grep -A30 '^\[General\]' "$TAUTULLI_INI" | grep 'api_key' | head -1 \
    | cut -d'=' -f2 | tr -d ' "' || true)
  if [[ -n "$TAUTULLI_KEY" ]]; then
    update_env "TAUTULLI_API_KEY" "$TAUTULLI_KEY"
    ok "Tautulli API key: ${TAUTULLI_KEY:0:8}... (saved to .env)"
  fi
fi

ok ".env updated"
todo_done "env-update"

# ─── Step 3: Wait for HTTP ────────────────────────────────────────────────────
header "Waiting for services to be ready"

wait_for_http "${RADARR_BASE}/api/v3/system/status"   "$RADARR_KEY"   "Radarr"
wait_for_http "${SONARR_BASE}/api/v3/system/status"   "$SONARR_KEY"   "Sonarr"
wait_for_http "${PROWLARR_BASE}/api/v1/system/status" "$PROWLARR_KEY" "Prowlarr"

# ─── Step 4: Root folders ─────────────────────────────────────────────────────
header "Configuring root folders"

RADARR_FOLDER="${RADARR_ROOT_FOLDER:-/media/movies}"
SONARR_FOLDER="${SONARR_ROOT_FOLDER:-/media/tv}"

existing_radarr_folders=$(arr_get "${RADARR_BASE}/api/v3/rootFolder" "$RADARR_KEY")
if echo "$existing_radarr_folders" | grep -q "\"path\":\"${RADARR_FOLDER}\""; then
  skip "Radarr root folder already set to ${RADARR_FOLDER}"
else
  result=$(arr_post "${RADARR_BASE}/api/v3/rootFolder" "$RADARR_KEY" "{\"path\":\"${RADARR_FOLDER}\"}")
  echo "$result" | grep -q '"id"' && ok "Radarr root folder → ${RADARR_FOLDER}" || warn "Radarr root folder may have failed: $result"
  todo_done "radarr-rootfolder"
fi

existing_sonarr_folders=$(arr_get "${SONARR_BASE}/api/v3/rootFolder" "$SONARR_KEY")
if echo "$existing_sonarr_folders" | grep -q "\"path\":\"${SONARR_FOLDER}\""; then
  skip "Sonarr root folder already set to ${SONARR_FOLDER}"
else
  result=$(arr_post "${SONARR_BASE}/api/v3/rootFolder" "$SONARR_KEY" "{\"path\":\"${SONARR_FOLDER}\"}")
  echo "$result" | grep -q '"id"' && ok "Sonarr root folder → ${SONARR_FOLDER}" || warn "Sonarr root folder may have failed: $result"
  todo_done "sonarr-rootfolder"
fi

# ─── Step 5: Connect Prowlarr → Radarr + Sonarr ───────────────────────────────
header "Connecting Prowlarr to Radarr and Sonarr"

# Probe which URL Radarr can actually use to reach Prowlarr.
# When VPN is on, Prowlarr shares gluetun's network stack.
echo -n "  Probing Prowlarr URL from Radarr container..."
PROWLARR_CONTAINER_URL=$(probe_url_from_radarr \
  "http://gluetun:9696/api/v1/system/status" \
  "http://prowlarr:9696/api/v1/system/status")
# Strip the path — we only need the base URL
PROWLARR_CONTAINER_URL="${PROWLARR_CONTAINER_URL%/api*}"
if [[ -n "$PROWLARR_CONTAINER_URL" ]]; then
  ok "Prowlarr reachable from Radarr at ${PROWLARR_CONTAINER_URL}"
else
  PROWLARR_CONTAINER_URL=$($USE_VPN && echo "http://gluetun:9696" || echo "http://prowlarr:9696")
  warn "Could not probe — defaulting to ${PROWLARR_CONTAINER_URL}"
fi

existing_apps=$(arr_get "${PROWLARR_BASE}/api/v1/applications" "$PROWLARR_KEY")

if already_exists "$existing_apps" "Radarr"; then
  skip "Radarr already connected to Prowlarr"
else
  payload=$(cat <<JSON
{
  "name": "Radarr",
  "syncLevel": "fullSync",
  "implementationName": "Radarr",
  "implementation": "Radarr",
  "configContract": "RadarrSettings",
  "fields": [
    {"name": "prowlarrUrl",             "value": "${PROWLARR_CONTAINER_URL}"},
    {"name": "baseUrl",                 "value": "http://radarr:7878"},
    {"name": "apiKey",                  "value": "${RADARR_KEY}"},
    {"name": "syncCategories",          "value": [2000,2010,2020,2030,2040,2045,2050,2060,2070,2080]},
    {"name": "animeSyncCategories",     "value": [2000]},
    {"name": "syncAnimeStandardFormat", "value": false}
  ],
  "tags": []
}
JSON
)
  result=$(arr_post_plain "${PROWLARR_BASE}/api/v1/applications" "$PROWLARR_KEY" "$payload")
  echo "$result" | grep -q '"id"' && { ok "Prowlarr → Radarr connected"; todo_done "prowlarr-radarr"; } \
    || warn "Prowlarr → Radarr may have failed: $(echo "$result" | head -c 200)"
fi

if already_exists "$existing_apps" "Sonarr"; then
  skip "Sonarr already connected to Prowlarr"
else
  payload=$(cat <<JSON
{
  "name": "Sonarr",
  "syncLevel": "fullSync",
  "implementationName": "Sonarr",
  "implementation": "Sonarr",
  "configContract": "SonarrSettings",
  "fields": [
    {"name": "prowlarrUrl",             "value": "${PROWLARR_CONTAINER_URL}"},
    {"name": "baseUrl",                 "value": "http://sonarr:8989"},
    {"name": "apiKey",                  "value": "${SONARR_KEY}"},
    {"name": "syncCategories",          "value": [5000,5010,5020,5030,5040,5045,5050,5060,5070,5080]},
    {"name": "animeSyncCategories",     "value": [5070]},
    {"name": "syncAnimeStandardFormat", "value": false}
  ],
  "tags": []
}
JSON
)
  result=$(arr_post_plain "${PROWLARR_BASE}/api/v1/applications" "$PROWLARR_KEY" "$payload")
  echo "$result" | grep -q '"id"' && { ok "Prowlarr → Sonarr connected"; todo_done "prowlarr-sonarr"; } \
    || warn "Prowlarr → Sonarr may have failed: $(echo "$result" | head -c 200)"
fi

# ─── Step 6: Add download clients to Radarr + Sonarr ─────────────────────────
if $USE_TORRENT; then
  header "Enabling Deluge Labels plugin"

  DELUGE_HOST=$($USE_VPN && echo "gluetun" || echo "deluge")
  DELUGE_PASS="${DELUGE_PASSWORD:-changeme}"

  # Full JSON-RPC flow: login → connect to daemon → enable plugin → create labels
  deluge_result=$(python3 << PYEOF
import json, http.cookiejar, urllib.request, urllib.error, time, sys

DELUGE_URL = "http://localhost:8112"
PASS = """${DELUGE_PASS}"""

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

def rpc(method, params, req_id):
    data = json.dumps({"method": method, "params": params, "id": req_id}).encode()
    req = urllib.request.Request(
        f"{DELUGE_URL}/json", data=data,
        headers={"Content-Type": "application/json"})
    return json.loads(opener.open(req).read())

try:
    r = rpc("auth.login", [PASS], 1)
    if not r.get("result"):
        print("LOGIN_FAILED"); sys.exit(1)

    hosts = rpc("web.get_hosts", [], 2).get("result", [])
    if hosts:
        rpc("web.connect", [hosts[0][0]], 3)
        time.sleep(2)

    rpc("core.enable_plugin", ["Label"], 4)
    rpc("web.enable_plugin", ["Label"], 5)
    time.sleep(3)

    for i, lbl in enumerate(["radarr", "sonarr"], start=6):
        rpc("label.add", [lbl], i)

    print("OK")
except Exception as e:
    print(f"ERROR: {e}"); sys.exit(1)
PYEOF
  )

  if [[ "$deluge_result" == "OK" ]]; then
    ok "Deluge Labels plugin enabled, labels created: radarr, sonarr"
  else
    warn "Deluge Labels setup failed: ${deluge_result} (check DELUGE_PASSWORD in .env)"
  fi

  header "Adding Deluge download client"

  for ARR in radarr sonarr; do
    BASE=$( [[ "$ARR" == "radarr" ]] && echo "$RADARR_BASE" || echo "$SONARR_BASE" )
    KEY=$(  [[ "$ARR" == "radarr" ]] && echo "$RADARR_KEY"  || echo "$SONARR_KEY"  )
    LABEL_CAP=$(echo "$ARR" | sed 's/./\u&/')

    existing_clients=$(arr_get "${BASE}/api/v3/downloadclient" "$KEY")
    if already_exists "$existing_clients" "Deluge"; then
      skip "Deluge already configured in ${LABEL_CAP}"
      continue
    fi

    payload=$(cat <<JSON
{
  "enable": true,
  "protocol": "torrent",
  "priority": 1,
  "name": "Deluge",
  "fields": [
    {"name": "host",                   "value": "${DELUGE_HOST}"},
    {"name": "port",                   "value": 8112},
    {"name": "password",               "value": "${DELUGE_PASS}"},
    {"name": "category",               "value": "${ARR}"},
    {"name": "recentMoviePriority",    "value": 0},
    {"name": "olderMoviePriority",     "value": 0},
    {"name": "recentEpisodePriority",  "value": 0},
    {"name": "olderEpisodePriority",   "value": 0},
    {"name": "addPaused",              "value": false},
    {"name": "useSsl",                 "value": false}
  ],
  "implementationName": "Deluge",
  "implementation": "Deluge",
  "configContract": "DelugeSettings",
  "tags": []
}
JSON
)
    result=$(arr_post "${BASE}/api/v3/downloadclient" "$KEY" "$payload")
    echo "$result" | grep -q '"id"' \
      && { ok "Deluge → ${LABEL_CAP} (host: ${DELUGE_HOST}:8112, label: ${ARR})"; todo_done "${ARR}-deluge"; } \
      || warn "Deluge → ${LABEL_CAP} may have failed: $(echo "$result" | head -c 200)"
  done
fi

if $USE_USENET; then
  header "Adding SABnzbd download client"

  SABNZBD_INI="${SCRIPT_DIR}/config/sabnzbd/sabnzbd.ini"
  if [[ ! -f "$SABNZBD_INI" ]]; then
    warn "SABnzbd config not found — is SABnzbd running? Skipping."
  else
    # SABnzbd rejects connections whose Host header isn't whitelisted.
    # Patch the INI to allow the 'sabnzbd' Docker hostname, then restart.
    if ! grep -q 'host_whitelist' "$SABNZBD_INI" || \
       ! grep 'host_whitelist' "$SABNZBD_INI" | grep -q 'sabnzbd'; then
      if grep -q '^host_whitelist' "$SABNZBD_INI"; then
        sed -i "s|^host_whitelist\s*=.*|host_whitelist = sabnzbd, localhost|" "$SABNZBD_INI"
      else
        sed -i "/^\[misc\]/a host_whitelist = sabnzbd, localhost" "$SABNZBD_INI"
      fi
      ok "SABnzbd host_whitelist patched"
    fi

    # Ensure movies and tv categories exist in sabnzbd.ini
    cat_result=$(python3 - "$SABNZBD_INI" << 'PYEOF'
import sys
ini_path = sys.argv[1]
with open(ini_path) as f:
    content = f.read()
changed = False
for cat in ["movies", "tv"]:
    if f"[[{cat}]]" not in content:
        block = (f"\n[[{cat}]]\n"
                 f"    name = {cat}\n"
                 f"    order = 0\n"
                 f"    pp = \"\"\n"
                 f"    script = Default\n"
                 f"    dir = \n"
                 f"    newzbin = \n"
                 f"    priority = -100\n")
        if "[categories]" in content:
            content = content.replace("[categories]\n", "[categories]\n" + block, 1)
        else:
            content += "\n[categories]\n" + block
        changed = True
if changed:
    with open(ini_path, "w") as f:
        f.write(content)
    print("UPDATED")
else:
    print("ALREADY_OK")
PYEOF
    )
    [[ "$cat_result" == "UPDATED" ]] && ok "SABnzbd categories added: movies, tv" \
      || skip "SABnzbd categories already present"

    ok "Restarting SABnzbd..."
    docker restart sabnzbd >/dev/null
    sleep 8

    SABNZBD_KEY=$(grep '^api_key' "$SABNZBD_INI" | head -1 | cut -d'=' -f2 | tr -d ' "' || true)
    if [[ -z "$SABNZBD_KEY" ]]; then
      warn "Could not read SABnzbd API key from sabnzbd.ini — skipping"
    else
      ok "SABnzbd API key: ${SABNZBD_KEY:0:8}..."
      update_env "SABNZBD_API_KEY" "$SABNZBD_KEY"

      for ARR in radarr sonarr; do
        BASE=$( [[ "$ARR" == "radarr" ]] && echo "$RADARR_BASE" || echo "$SONARR_BASE" )
        KEY=$(  [[ "$ARR" == "radarr" ]] && echo "$RADARR_KEY"  || echo "$SONARR_KEY"  )
        LABEL=$(echo "$ARR" | sed 's/./\u&/')

        existing_clients=$(arr_get "${BASE}/api/v3/downloadclient" "$KEY")
        if already_exists "$existing_clients" "SABnzbd"; then
          skip "SABnzbd already configured in ${LABEL}"
          continue
        fi

        payload=$(cat <<JSON
{
  "enable": true,
  "protocol": "usenet",
  "priority": 1,
  "name": "SABnzbd",
  "fields": [
    {"name": "host",                   "value": "sabnzbd"},
    {"name": "port",                   "value": 8080},
    {"name": "apiKey",                 "value": "${SABNZBD_KEY}"},
    {"name": "username",               "value": ""},
    {"name": "password",               "value": ""},
    {"name": "movieCategory",          "value": "movies"},
    {"name": "tvCategory",             "value": "tv"},
    {"name": "recentMoviePriority",    "value": -100},
    {"name": "olderMoviePriority",     "value": -100},
    {"name": "recentEpisodePriority",  "value": -100},
    {"name": "olderEpisodePriority",   "value": -100},
    {"name": "useSsl",                 "value": false}
  ],
  "implementationName": "Sabnzbd",
  "implementation": "Sabnzbd",
  "configContract": "SabnzbdSettings",
  "tags": []
}
JSON
)
        result=$(arr_post "${BASE}/api/v3/downloadclient" "$KEY" "$payload")
        echo "$result" | grep -q '"id"' \
          && { ok "SABnzbd → ${LABEL}"; todo_done "${ARR}-sabnzbd"; } \
          || warn "SABnzbd → ${LABEL} may have failed: $(echo "$result" | head -c 200)"
      done
    fi
  fi
fi

# ─── Step 7: Restart Trakt containers with updated keys ───────────────────────
if $USE_TRAKT; then
  header "Restarting Trakt containers with updated API keys"
  cd "${SCRIPT_DIR}"
  eval "$COMPOSE_CMD restart trakt-watchlist-sync trakt-watchlist-cleanup" 2>/dev/null \
    && { ok "Trakt containers restarted"; todo_done "trakt-restart"; } \
    || warn "Could not restart Trakt containers (may not be running yet)"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Auto-configuration complete.${RESET}"
echo ""
echo "Remaining manual steps are in TODO.md"
if $USE_TRAKT; then
  echo ""
  echo -e "  ${YELLOW}Trakt OAuth still needed:${RESET}"
  COMPOSE_FILES_DISPLAY=$(grep 'docker compose' "${SCRIPT_DIR}/start.sh" | head -1 | sed 's/ up -d.*//' | sed "s|cd.*&&||" | xargs)
  echo "  $COMPOSE_FILES_DISPLAY run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup"
fi
echo ""
