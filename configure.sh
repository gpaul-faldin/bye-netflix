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
USE_TORRENT=false; USE_USENET=false; USE_VPN=false; USE_TRAKT=false; USE_BAZARR=false
grep -q 'compose/torrent.yml' "${SCRIPT_DIR}/start.sh" && USE_TORRENT=true
grep -q 'compose/usenet.yml'  "${SCRIPT_DIR}/start.sh" && USE_USENET=true
grep -q 'compose/vpn.yml'     "${SCRIPT_DIR}/start.sh" && USE_VPN=true
grep -q 'compose/trakt.yml'   "${SCRIPT_DIR}/start.sh" && USE_TRAKT=true
grep -q 'compose/bazarr.yml'  "${SCRIPT_DIR}/start.sh" && USE_BAZARR=true

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
already_exists() { echo "$1" | grep -q "\"name\": *\"$2\""; }

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
if echo "$existing_radarr_folders" | tr -d ' \t\n\r' | grep -q "\"path\":\"${RADARR_FOLDER}\""; then
  skip "Radarr root folder already set to ${RADARR_FOLDER}"
else
  result=$(arr_post "${RADARR_BASE}/api/v3/rootFolder" "$RADARR_KEY" "{\"path\":\"${RADARR_FOLDER}\"}")
  echo "$result" | grep -q '"id"' && ok "Radarr root folder → ${RADARR_FOLDER}" || warn "Radarr root folder may have failed: $result"
  todo_done "radarr-rootfolder"
fi

existing_sonarr_folders=$(arr_get "${SONARR_BASE}/api/v3/rootFolder" "$SONARR_KEY")
if echo "$existing_sonarr_folders" | tr -d ' \t\n\r' | grep -q "\"path\":\"${SONARR_FOLDER}\""; then
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
  echo "$result" | grep -q '"id"'           && { ok "Prowlarr → Radarr connected"; todo_done "prowlarr-radarr"; } \
    || echo "$result" | grep -q 'Should be unique' && skip "Radarr already connected to Prowlarr" \
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
  echo "$result" | grep -q '"id"'           && { ok "Prowlarr → Sonarr connected"; todo_done "prowlarr-sonarr"; } \
    || echo "$result" | grep -q 'Should be unique' && skip "Sonarr already connected to Prowlarr" \
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
    # Patch sabnzbd.ini: hostname whitelist + correct download paths
    ini_needs_restart=false

    if ! grep -q 'host_whitelist' "$SABNZBD_INI" || \
       ! grep 'host_whitelist' "$SABNZBD_INI" | grep -q 'sabnzbd'; then
      if grep -q '^host_whitelist' "$SABNZBD_INI"; then
        sed -i "s|^host_whitelist\s*=.*|host_whitelist = sabnzbd, localhost|" "$SABNZBD_INI"
      else
        sed -i "/^\[misc\]/a host_whitelist = sabnzbd, localhost" "$SABNZBD_INI"
      fi
      ok "SABnzbd host_whitelist patched"
      ini_needs_restart=true
    fi

    # Point download dirs to /downloads (mounted from DOWNLOADS_DIR), not /config
    sab_dirs_result=$(python3 - "$SABNZBD_INI" << 'PYEOF'
import sys, re
ini_path = sys.argv[1]
with open(ini_path) as f:
    content = f.read()
targets = [('download_dir', '/downloads/incomplete'), ('complete_dir', '/downloads/complete')]
changes = []
for key, val in targets:
    m = re.search(rf'^{re.escape(key)}\s*=\s*(.*)$', content, re.MULTILINE)
    current = m.group(1).strip() if m else ''
    if current != val:
        if m:
            content = re.sub(rf'^{re.escape(key)}\s*=.*$', f'{key} = {val}', content, flags=re.MULTILINE)
        else:
            content = re.sub(r'(\[misc\])', rf'\1\n{key} = {val}', content, count=1)
        changes.append(key)
if changes:
    with open(ini_path, 'w') as f:
        f.write(content)
    print('UPDATED:' + ','.join(changes))
else:
    print('ALREADY_OK')
PYEOF
    )
    if [[ "$sab_dirs_result" == UPDATED:* ]]; then
      ok "SABnzbd download paths set: ${sab_dirs_result#UPDATED:}"
      ini_needs_restart=true
    else
      skip "SABnzbd download paths already correct"
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

    if $ini_needs_restart; then
      ok "Restarting SABnzbd to apply config changes..."
      docker restart sabnzbd >/dev/null
      sleep 8
    fi

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

# ─── Step 7: Configure Fetcharr ──────────────────────────────────────────────
header "Configuring Fetcharr"

PLEX_PREFS="${SCRIPT_DIR}/config/plex/Library/Application Support/Plex Media Server/Preferences.xml"
FETCHARR_CFG="${SCRIPT_DIR}/config/fetcharr/fetcharr.yaml"
PLEX_TOKEN=""

if [[ -f "$PLEX_PREFS" ]]; then
  PLEX_TOKEN=$(grep -oP '(?<=PlexOnlineToken=")[^"]+' "$PLEX_PREFS" 2>/dev/null || true)
  if [[ -n "$PLEX_TOKEN" ]]; then
    update_env "PLEX_TOKEN" "$PLEX_TOKEN"
    ok "Plex token found: ${PLEX_TOKEN:0:8}..."
  else
    warn "PlexOnlineToken not found in Preferences.xml — have you signed into Plex yet?"
  fi
else
  warn "Plex config not found — is Plex running? Skipping Fetcharr config."
fi

if [[ -n "$PLEX_TOKEN" ]]; then
  RADARR_QUALITY=$(echo "${RADARR_QUALITY_PROFILE:-any}" | tr '[:upper:]' '[:lower:]')
  SONARR_QUALITY=$(echo "${SONARR_QUALITY_PROFILE:-any}" | tr '[:upper:]' '[:lower:]')

  cat > "$FETCHARR_CFG" <<YAML
plex:
  api_token: ${PLEX_TOKEN}
  sync_friends_watchlist: false

sonarr:
  default:
    base_url: http://sonarr:8989
    api_key: ${SONARR_KEY}
    quality_profile: ${SONARR_QUALITY}
    root_folder: ${SONARR_ROOT_FOLDER:-/media/tv}
    update_existing: false

radarr:
  default:
    base_url: http://radarr:7878
    api_key: ${RADARR_KEY}
    quality_profile: ${RADARR_QUALITY}
    root_folder: ${RADARR_ROOT_FOLDER:-/media/movies}
    update_existing: false
YAML
  ok "Fetcharr config written → ${FETCHARR_CFG}"
  docker restart fetcharr >/dev/null 2>&1 && ok "Fetcharr restarted" || true
  todo_done "fetcharr-config"
else
  warn "Fetcharr config skipped — set PLEX_TOKEN in .env and re-run configure.sh"
fi

# ─── Step 8: Configure Tautulli scripts ──────────────────────────────────────
header "Configuring Tautulli scripts"

SCRIPTS_SRC="${SCRIPT_DIR}/tautulliScripts"
SCRIPTS_DEST="${SCRIPT_DIR}/config/tautulli/scripts"

if [[ ! -d "$SCRIPTS_SRC" ]]; then
  warn "tautulliScripts/ not found — skipping Tautulli setup"
else
  mkdir -p "$SCRIPTS_DEST"

  # ── Tautulli API key (re-read if not already set from Step 2) ─────────────
  TAUTULLI_INI="${SCRIPT_DIR}/config/tautulli/config/config.ini"
  if [[ -z "${TAUTULLI_KEY:-}" ]]; then
    wait_for_file "$TAUTULLI_INI" "Tautulli" \
      && TAUTULLI_KEY=$(grep -A30 '^\[General\]' "$TAUTULLI_INI" | grep 'api_key' \
           | head -1 | cut -d'=' -f2 | tr -d ' "' || true) \
      || true
    [[ -n "$TAUTULLI_KEY" ]] && update_env "TAUTULLI_API_KEY" "$TAUTULLI_KEY"
  fi

  # ── Copy + patch trakt_scrobbler.py ──────────────────────────────────────
  SCROBBLER_SRC="${SCRIPTS_SRC}/trakt_scrobbler.py"
  SCROBBLER_DEST="${SCRIPTS_DEST}/trakt_scrobbler.py"
  if [[ -f "$SCROBBLER_SRC" ]]; then
    cp "$SCROBBLER_SRC" "$SCROBBLER_DEST"
    [[ -n "${TRAKT_CLIENT_ID:-}"     ]] && sed -i "s|^TRAKT_CLIENT_ID = .*|TRAKT_CLIENT_ID = '${TRAKT_CLIENT_ID}'|"         "$SCROBBLER_DEST"
    [[ -n "${TRAKT_CLIENT_SECRET:-}" ]] && sed -i "s|^TRAKT_CLIENT_SECRET = .*|TRAKT_CLIENT_SECRET = '${TRAKT_CLIENT_SECRET}'|" "$SCROBBLER_DEST"
    [[ -n "${TAUTULLI_KEY:-}"        ]] && sed -i "s|^TAUTULLI_API_KEY = .*|TAUTULLI_API_KEY = '${TAUTULLI_KEY}'|"           "$SCROBBLER_DEST"
    ok "trakt_scrobbler.py → config/tautulli/scripts/ (credentials patched)"
  fi

  # ── Copy + patch plex_progressive_downloader.py ───────────────────────────
  DOWNLOADER_SRC="${SCRIPTS_SRC}/plex_progressive_downloader.py"
  DOWNLOADER_DEST="${SCRIPTS_DEST}/plex_progressive_downloader.py"
  if [[ -f "$DOWNLOADER_SRC" ]]; then
    cp "$DOWNLOADER_SRC" "$DOWNLOADER_DEST"
    sed -i "s|^SONARR_APIKEY = .*|SONARR_APIKEY = '${SONARR_KEY}'|" "$DOWNLOADER_DEST"
    ok "plex_progressive_downloader.py → config/tautulli/scripts/ (credentials patched)"
  fi

  # ──Install dep ───────────────────────────
  docker exec tautulli pip install requests -q

  todo_done "tautulli-scripts"

  # ── Trakt scrobbler OAuth ─────────────────────────────────────────────────
  if $USE_TRAKT && [[ -f "${SCROBBLER_DEST:-}" ]]; then
    SCROBBLER_TOKEN="${SCRIPTS_DEST}/trakt_tokens.json"
    if [[ -f "$SCROBBLER_TOKEN" ]]; then
      skip "Trakt scrobbler already authenticated"
    else
      header "Authenticating Trakt scrobbler"
      echo ""
      echo -e "  ${YELLOW}Action required: a URL and code will appear below.${RESET}"
      echo -e "  ${YELLOW}Open the URL in your browser, enter the code, then come back.${RESET}"
      echo ""
      (cd "${SCRIPTS_DEST}" && python3 trakt_scrobbler.py --setup) \
        && ok "Trakt scrobbler authenticated — token saved" \
        || warn "Scrobbler auth failed — re-run: cd ${SCRIPTS_DEST} && python3 trakt_scrobbler.py --setup"
    fi
  fi
fi

# ─── Step 9: Connect Bazarr to Radarr + Sonarr ───────────────────────────────
if $USE_BAZARR; then
  header "Connecting Bazarr to Radarr and Sonarr"

  # Bazarr stores its connection settings in config.yaml — there are no API
  # endpoints to configure Sonarr/Radarr, so we edit the file directly.
  BAZARR_CFG=""
  for cfg in "${SCRIPT_DIR}/config/bazarr/config/config.yaml" \
             "${SCRIPT_DIR}/config/bazarr/data/config.yaml"; do
    [[ -f "$cfg" ]] && { BAZARR_CFG="$cfg"; break; }
  done

  if [[ -z "$BAZARR_CFG" ]]; then
    wait_for_file "${SCRIPT_DIR}/config/bazarr/config/config.yaml" "Bazarr" \
      && BAZARR_CFG="${SCRIPT_DIR}/config/bazarr/config/config.yaml"
  fi

  if [[ -z "$BAZARR_CFG" || ! -f "$BAZARR_CFG" ]]; then
    warn "Bazarr config.yaml not found — is Bazarr running? Skipping."
  else
    bazarr_result=$(python3 << PYEOF
import re, sys

cfg_path   = "${BAZARR_CFG}"
sonarr_key = "${SONARR_KEY}"
radarr_key = "${RADARR_KEY}"

with open(cfg_path) as f:
    content = f.read()

def get_val(content, section, key):
    m = re.search(rf'\n{section}:(?:\n  [^\n]*){{0,30}}\n  {key}:\s*(\S+)', content)
    return m.group(1) if m else None

def set_val(content, section, key, value):
    pattern = rf'(\n{section}:(?:\n  [^\n]*){{0,30}}\n  {key}:\s*)(\S+)'
    new, n = re.subn(pattern, lambda m: m.group(1) + value, content, count=1)
    if n:
        return new, True
    # Section exists but key is missing — insert after section header line
    pattern = rf'(\n{section}:\n)'
    new, n = re.subn(pattern, lambda m: m.group(1) + f'  {key}: {value}\n', content, count=1)
    if n:
        return new, True
    # Section missing entirely — append
    return content.rstrip('\n') + f'\n{section}:\n  {key}: {value}\n', True

changes = []
for section, key, ip, port, apikey in [
    ('sonarr', 'apikey', 'sonarr', 8989, sonarr_key),
    ('radarr', 'apikey', 'radarr', 7878, radarr_key),
]:
    if get_val(content, section, 'ip') is None:
        # Section missing — write the whole block
        content = content.rstrip('\n') + (
            f'\n{section}:\n  ip: {ip}\n  port: {port}\n'
            f'  apikey: {apikey}\n  ssl: false\n  base_url: ""\n'
        )
        changes.append(section)
    elif get_val(content, section, key) != apikey:
        content, _ = set_val(content, section, key, apikey)
        changes.append(section)

if changes:
    with open(cfg_path, 'w') as f:
        f.write(content)
    print('UPDATED:' + ','.join(changes))
else:
    print('ALREADY_OK')
PYEOF
    )

    if [[ "$bazarr_result" == UPDATED:* ]]; then
      ok "Bazarr config updated (${bazarr_result#UPDATED:}) — restarting Bazarr"
      docker restart bazarr >/dev/null 2>&1 || true
    elif [[ "$bazarr_result" == "ALREADY_OK" ]]; then
      skip "Bazarr already connected to Radarr and Sonarr"
    else
      warn "Bazarr config update failed: $bazarr_result"
      warn "Configure manually: http://localhost:6767 → Settings → Sonarr / Radarr"
    fi
  fi
fi

# ─── Step 10: Trakt cleanup webhooks ─────────────────────────────────────────
if $USE_TRAKT; then
  header "Configuring Trakt cleanup webhooks"

  WEBHOOK_URL_RADARR="http://trakt-watchlist-cleanup:5000/radarr"
  WEBHOOK_URL_SONARR="http://trakt-watchlist-cleanup:5000/sonarr"

  # Radarr — on movie delete
  existing=$(arr_get "${RADARR_BASE}/api/v3/notification" "$RADARR_KEY")
  if already_exists "$existing" "Trakt Cleanup"; then
    skip "Trakt Cleanup webhook already in Radarr"
  else
    payload=$(cat <<JSON
{
  "name": "Trakt Cleanup",
  "onMovieDelete": true,
  "implementation": "Webhook",
  "configContract": "WebhookSettings",
  "fields": [
    {"name": "url",      "value": "${WEBHOOK_URL_RADARR}"},
    {"name": "method",   "value": 1},
    {"name": "username", "value": ""},
    {"name": "password", "value": ""}
  ],
  "tags": []
}
JSON
)
    result=$(arr_post_plain "${RADARR_BASE}/api/v3/notification" "$RADARR_KEY" "$payload")
    echo "$result" | grep -q '"id"' \
      && ok "Radarr → Trakt Cleanup webhook configured" \
      || warn "Radarr webhook failed: $(echo "$result" | head -c 200)"
  fi

  # Sonarr — on series delete
  existing=$(arr_get "${SONARR_BASE}/api/v3/notification" "$SONARR_KEY")
  if already_exists "$existing" "Trakt Cleanup"; then
    skip "Trakt Cleanup webhook already in Sonarr"
  else
    payload=$(cat <<JSON
{
  "name": "Trakt Cleanup",
  "onSeriesDelete": true,
  "implementation": "Webhook",
  "configContract": "WebhookSettings",
  "fields": [
    {"name": "url",      "value": "${WEBHOOK_URL_SONARR}"},
    {"name": "method",   "value": 1},
    {"name": "username", "value": ""},
    {"name": "password", "value": ""}
  ],
  "tags": []
}
JSON
)
    result=$(arr_post_plain "${SONARR_BASE}/api/v3/notification" "$SONARR_KEY" "$payload")
    echo "$result" | grep -q '"id"' \
      && ok "Sonarr → Trakt Cleanup webhook configured" \
      || warn "Sonarr webhook failed: $(echo "$result" | head -c 200)"
  fi
fi

# ─── Step 11: Create Plex libraries ──────────────────────────────────────────
if [[ -n "${PLEX_TOKEN:-}" ]]; then
  header "Creating Plex libraries"

  PLEX_BASE="http://localhost:32400"

  # Wait for Plex to respond
  echo -n "  Waiting for Plex..."
  for _ in $(seq 1 20); do
    code=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "X-Plex-Token: $PLEX_TOKEN" "${PLEX_BASE}/library/sections" 2>/dev/null || true)
    [[ "$code" == "200" ]] && { echo " ready"; break; }
    sleep 3; echo -n "."
  done
  echo ""

  existing_libs=$(curl -s -H "X-Plex-Token: $PLEX_TOKEN" \
    -H "Accept: application/json" "${PLEX_BASE}/library/sections" 2>/dev/null || true)

  if echo "$existing_libs" | grep -q '"type":"movie"'; then
    skip "Plex Movies library already exists"
  else
    result=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "${PLEX_BASE}/library/sections?name=Movies&type=movie&agent=tv.plex.agents.movie&scanner=Plex+Movie&language=en-US&location=/media/movies" \
      -H "X-Plex-Token: $PLEX_TOKEN" 2>/dev/null || true)
    [[ "$result" == "200" || "$result" == "201" ]] \
      && ok "Plex Movies library created (→ /media/movies)" \
      || warn "Plex Movies library creation failed (HTTP $result) — create it manually in Plex"
  fi

  if echo "$existing_libs" | grep -q '"type":"show"'; then
    skip "Plex TV Shows library already exists"
  else
    result=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "${PLEX_BASE}/library/sections?name=TV+Shows&type=show&agent=tv.plex.agents.series&scanner=Plex+TV+Series&language=en-US&location=/media/tv" \
      -H "X-Plex-Token: $PLEX_TOKEN" 2>/dev/null || true)
    [[ "$result" == "200" || "$result" == "201" ]] \
      && ok "Plex TV Shows library created (→ /media/tv)" \
      || warn "Plex TV Shows library creation failed (HTTP $result) — create it manually in Plex"
  fi
fi

# ─── Step 12: Restart Trakt containers ───────────────────────────────────────
if $USE_TRAKT; then
  header "Restarting Trakt containers with updated API keys"
  cd "${SCRIPT_DIR}"
  eval "$COMPOSE_CMD restart trakt-watchlist-sync trakt-watchlist-cleanup" 2>/dev/null \
    && { ok "Trakt containers restarted"; todo_done "trakt-restart"; } \
    || warn "Could not restart Trakt containers (may not be running yet)"
fi

# ─── Step 13: Trakt watchlist sync OAuth ─────────────────────────────────────
if $USE_TRAKT; then
  SYNC_TOKEN="${SCRIPT_DIR}/config/trakt-watchlist-sync/trakt_tokens.json"
  if [[ -f "$SYNC_TOKEN" ]]; then
    skip "Trakt watchlist sync already authenticated"
  else
    header "Authenticating Trakt watchlist sync"
    echo ""
    echo -e "  ${YELLOW}Action required: a URL and code will appear below.${RESET}"
    echo -e "  ${YELLOW}Open the URL in your browser, enter the code, then come back.${RESET}"
    echo ""
    cd "${SCRIPT_DIR}"
    eval "$COMPOSE_CMD run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup" \
      && ok "Trakt watchlist sync authenticated — token saved" \
      || warn "Watchlist sync auth failed — re-run: $COMPOSE_CMD run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup"

    # Restart so the running container picks up the new token
    eval "$COMPOSE_CMD restart trakt-watchlist-sync" 2>/dev/null || true
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Auto-configuration complete.${RESET}"
echo ""
echo "Remaining manual steps are in TODO.md"
echo ""
