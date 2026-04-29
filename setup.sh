#!/usr/bin/env bash
# Interactive setup script — generates .env and start.sh for your configuration.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

header() { echo -e "\n${CYAN}${BOLD}$1${RESET}"; }
ask()    { echo -e "${YELLOW}$1${RESET}"; }
ok()     { echo -e "${GREEN}✓ $1${RESET}"; }
warn()   { echo -e "${RED}⚠ $1${RESET}"; }

prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="$3"
  local input
  if [[ -n "$default" ]]; then
    read -rp "$(echo -e "${YELLOW}${prompt_text} [${default}]: ${RESET}")" input
    echo "${input:-$default}"
  else
    read -rp "$(echo -e "${YELLOW}${prompt_text}: ${RESET}")" input
    echo "$input"
  fi
}

yes_no() {
  local prompt_text="$1"
  local default="${2:-n}"
  local input
  read -rp "$(echo -e "${YELLOW}${prompt_text} [$(echo "$default" | tr '[:lower:]' '[:upper:]')/$(if [[ "$default" == "y" ]]; then echo "n"; else echo "y"; fi)]: ${RESET}")" input
  input="${input:-$default}"
  [[ "$input" =~ ^[Yy] ]]
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║        Bye Netflix — Setup Script        ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo "This script generates your .env and start.sh based on your hardware and preferences."
echo "You can re-run it at any time to reconfigure."

# ─── System ──────────────────────────────────────────────────────────────────
header "System"

TZ=$(prompt TZ "Timezone (e.g. America/New_York, Europe/London)" "Europe/Paris")

PUID=$(id -u)
PGID=$(id -g)
ok "Detected user IDs: PUID=$PUID PGID=$PGID"

# ─── Storage ─────────────────────────────────────────────────────────────────
header "Storage"

echo "Two supported configurations:"
echo "  Single drive  — downloads and media library share the same drive"
echo "  SSD + HDD     — downloads land on the SSD, Radarr/Sonarr import them to the HDD"
echo ""

MEDIA_DIR=$(prompt MEDIA_DIR "Media library path (HDD — where movies/TV are stored)" "/srv/media")

DOWNLOADS_DIR="${MEDIA_DIR}/downloads"
if yes_no "Do you have a separate SSD for downloads? (faster during active downloads)"; then
  DOWNLOADS_DIR=$(prompt DOWNLOADS_DIR "Downloads path (SSD)" "/mnt/ssd/downloads")
  echo ""
  echo "  Note: Radarr/Sonarr will copy files from SSD → HDD on import."
  echo "  (Hardlinks won't work across drives — this is expected.)"
else
  DOWNLOADS_DIR=$(prompt DOWNLOADS_DIR "Downloads directory" "${MEDIA_DIR}/downloads")
fi

# ─── Download method ─────────────────────────────────────────────────────────
header "Download Method"

echo "  1) Torrents only"
echo "  2) Usenet only"
echo "  3) Both torrents and usenet"
DL_CHOICE=""
while [[ ! "$DL_CHOICE" =~ ^[123]$ ]]; do
  read -rp "$(echo -e "${YELLOW}Choose [1/2/3]: ${RESET}")" DL_CHOICE
  DL_CHOICE="${DL_CHOICE:-1}"
done

USE_TORRENT=false
USE_USENET=false
DELUGE_PASSWORD="changeme"

if [[ "$DL_CHOICE" == "1" || "$DL_CHOICE" == "3" ]]; then
  USE_TORRENT=true
  DELUGE_PASSWORD=$(prompt DELUGE_PASSWORD "Deluge WebUI password" "changeme")
fi
if [[ "$DL_CHOICE" == "2" || "$DL_CHOICE" == "3" ]]; then
  USE_USENET=true
fi

# ─── VPN ─────────────────────────────────────────────────────────────────────
USE_VPN=false
VPN_FORWARDED_PORT="0"
VPN_FIREWALL_SUBNETS="172.18.0.0/16,172.19.0.0/16,192.168.1.0/24"

if $USE_TORRENT; then
  header "VPN"
  echo "A VPN routes your torrent traffic through an encrypted tunnel."
  echo "Gluetun supports AirVPN, Mullvad, ProtonVPN, NordVPN, and more."
  echo "(See: https://github.com/qdm12/gluetun/wiki)"

  if yes_no "Route torrent traffic through a VPN?" "y"; then
    USE_VPN=true
    echo ""
    echo "Place your VPN provider's .ovpn or WireGuard config file at:"
    echo "  ${SCRIPT_DIR}/config/gluetun/vpn.ovpn"
    echo "(or edit docker-compose.vpn.yml to match your provider's env vars)"
    echo ""
    VPN_FORWARDED_PORT=$(prompt VPN_FORWARDED_PORT "Port forwarded by your VPN provider (for seeding, 0 to skip)" "0")
    VPN_FIREWALL_SUBNETS=$(prompt VPN_FIREWALL_SUBNETS "Docker + LAN subnets to allow through the VPN firewall" "$VPN_FIREWALL_SUBNETS")
  fi
fi

# ─── Trakt ───────────────────────────────────────────────────────────────────
header "Trakt Integration"
echo "Trakt sync automatically downloads anything you add to your Trakt watchlist."
echo "Trakt cleanup removes items from your watchlist when you delete them locally."

USE_TRAKT=false
TRAKT_CLIENT_ID=""
TRAKT_CLIENT_SECRET=""

if yes_no "Sync with Trakt.tv?" "y"; then
  USE_TRAKT=true
  echo ""
  echo "Create a Trakt API app at: https://trakt.tv/oauth/applications/new"
  echo "  Redirect URI: urn:ietf:wg:oauth:2.0:oob"
  echo ""
  TRAKT_CLIENT_ID=$(prompt TRAKT_CLIENT_ID "Trakt Client ID" "")
  TRAKT_CLIENT_SECRET=$(prompt TRAKT_CLIENT_SECRET "Trakt Client Secret" "")
fi

# ─── Plex ────────────────────────────────────────────────────────────────────
header "Plex"

echo "Get a one-time claim token at: https://www.plex.tv/claim  (expires in 4 minutes)"
PLEX_CLAIM=$(prompt PLEX_CLAIM "Plex claim token (leave blank to skip, set later)" "")

# ─── macvlan ─────────────────────────────────────────────────────────────────
header "Plex LAN IP (optional)"
echo "Assigning Plex a dedicated LAN IP improves local streaming reliability."
echo "Your host machine needs to be connected via an interface that supports macvlan."

USE_MACVLAN=false
PLEX_LAN_IP="192.168.1.100"
PLEX_LAN_INTERFACE="eth0"
PLEX_LAN_SUBNET="192.168.1.0/24"
PLEX_LAN_GATEWAY="192.168.1.1"

if yes_no "Give Plex a dedicated LAN IP (macvlan)?"; then
  USE_MACVLAN=true
  echo ""
  echo "Available network interfaces:"
  ip -o link show | awk -F': ' '{print "  " $2}' | grep -v lo
  echo ""
  PLEX_LAN_INTERFACE=$(prompt PLEX_LAN_INTERFACE "Host network interface" "eth0")
  PLEX_LAN_IP=$(prompt PLEX_LAN_IP "Unused LAN IP to assign to Plex" "192.168.1.100")
  PLEX_LAN_SUBNET=$(prompt PLEX_LAN_SUBNET "LAN subnet" "192.168.1.0/24")
  PLEX_LAN_GATEWAY=$(prompt PLEX_LAN_GATEWAY "Router/gateway IP" "192.168.1.1")
fi

# ─── Bazarr ──────────────────────────────────────────────────────────────────
header "Subtitles"
echo "Bazarr automatically downloads subtitles for your movies and TV shows."

USE_BAZARR=false
if yes_no "Enable Bazarr (automatic subtitles)?" "y"; then
  USE_BAZARR=true
fi

# ─── Radarr/Sonarr root folders ──────────────────────────────────────────────
header "Media Root Folders"
echo "These are the paths INSIDE containers where Radarr/Sonarr store media."

RADARR_ROOT_FOLDER=$(prompt RADARR_ROOT_FOLDER "Radarr root folder (inside container)" "/media/movies")
SONARR_ROOT_FOLDER=$(prompt SONARR_ROOT_FOLDER "Sonarr root folder (inside container)" "/media/tv")

# ─── Write .env ──────────────────────────────────────────────────────────────
header "Writing .env"

cat > "${SCRIPT_DIR}/.env" <<EOF
## Generated by setup.sh on $(date)
## Re-run setup.sh to regenerate, or edit manually.

# ─── System ──────────────────────────────────────────────────────────────────
TZ=${TZ}
PUID=${PUID}
PGID=${PGID}

# ─── Storage ─────────────────────────────────────────────────────────────────
MEDIA_DIR=${MEDIA_DIR}
DOWNLOADS_DIR=${DOWNLOADS_DIR}

# ─── Plex ────────────────────────────────────────────────────────────────────
PLEX_CLAIM=${PLEX_CLAIM}

# ─── Torrent client ──────────────────────────────────────────────────────────
DELUGE_PASSWORD=${DELUGE_PASSWORD}

# ─── VPN ─────────────────────────────────────────────────────────────────────
VPN_FORWARDED_PORT=${VPN_FORWARDED_PORT}
VPN_FIREWALL_SUBNETS=${VPN_FIREWALL_SUBNETS}

# ─── Trakt ───────────────────────────────────────────────────────────────────
TRAKT_CLIENT_ID=${TRAKT_CLIENT_ID}
TRAKT_CLIENT_SECRET=${TRAKT_CLIENT_SECRET}
# Fill these in after first run (Settings → General → API Key in each app):
RADARR_API_KEY=
SONARR_API_KEY=
RADARR_ROOT_FOLDER=${RADARR_ROOT_FOLDER}
SONARR_ROOT_FOLDER=${SONARR_ROOT_FOLDER}
RADARR_QUALITY_PROFILE=Any
SONARR_QUALITY_PROFILE=Any

# ─── macvlan ─────────────────────────────────────────────────────────────────
PLEX_LAN_IP=${PLEX_LAN_IP}
PLEX_LAN_INTERFACE=${PLEX_LAN_INTERFACE}
PLEX_LAN_SUBNET=${PLEX_LAN_SUBNET}
PLEX_LAN_GATEWAY=${PLEX_LAN_GATEWAY}
EOF

ok ".env written"

# ─── Write start.sh ──────────────────────────────────────────────────────────
header "Writing start.sh"

COMPOSE_FILES="-f docker-compose.yml"
$USE_TORRENT && COMPOSE_FILES="$COMPOSE_FILES -f compose/torrent.yml"
$USE_USENET  && COMPOSE_FILES="$COMPOSE_FILES -f compose/usenet.yml"
$USE_VPN     && COMPOSE_FILES="$COMPOSE_FILES -f compose/vpn.yml"
$USE_TRAKT   && COMPOSE_FILES="$COMPOSE_FILES -f compose/trakt.yml"
$USE_MACVLAN && COMPOSE_FILES="$COMPOSE_FILES -f compose/macvlan.yml"
$USE_BAZARR  && COMPOSE_FILES="$COMPOSE_FILES -f compose/bazarr.yml"

VPN_CHECK=""
if $USE_VPN; then
  VPN_CHECK='
if [[ ! -f "config/gluetun/vpn.ovpn" ]]; then
  echo "ERROR: VPN config not found at config/gluetun/vpn.ovpn"
  echo "Download your .ovpn from your VPN provider and place it there before starting."
  exit 1
fi
'
fi

cat > "${SCRIPT_DIR}/start.sh" <<EOF
#!/usr/bin/env bash
# Generated by setup.sh on $(date)
# Run this to start your stack.
cd "\$(dirname "\${BASH_SOURCE[0]}")"
${VPN_CHECK}
docker compose ${COMPOSE_FILES} up -d "\$@"
EOF

cat > "${SCRIPT_DIR}/stop.sh" <<EOF
#!/usr/bin/env bash
# Generated by setup.sh on $(date)
# Run this to stop your stack.
cd "\$(dirname "\${BASH_SOURCE[0]}")"
docker compose ${COMPOSE_FILES} down "\$@"
EOF

chmod +x "${SCRIPT_DIR}/start.sh" "${SCRIPT_DIR}/stop.sh"
ok "start.sh written: docker compose ${COMPOSE_FILES} up -d"

# ─── Create config directories ───────────────────────────────────────────────
header "Creating config directories"

DIRS="plex radarr sonarr prowlarr tautulli/config tautulli/scripts fetcharr trakt-watchlist-sync"
$USE_TORRENT && DIRS="$DIRS deluge"
$USE_USENET  && DIRS="$DIRS sabnzbd"
$USE_VPN     && DIRS="$DIRS gluetun"
$USE_BAZARR  && DIRS="$DIRS bazarr"

for d in $DIRS; do
  mkdir -p "${SCRIPT_DIR}/config/$d"
done
ok "Config directories created under ./config/"

# ─── Create media directories ────────────────────────────────────────────────
mkdir -p "${MEDIA_DIR}/movies" "${MEDIA_DIR}/tv" "${DOWNLOADS_DIR}"
ok "Media directories created"

# ─── Write TODO.md ───────────────────────────────────────────────────────────
header "Writing TODO.md"

TODO="${SCRIPT_DIR}/TODO.md"

cat > "$TODO" <<EOF
# Setup Progress

Generated by \`setup.sh\` on $(date)

Run \`./configure.sh\` after \`./start.sh\` to auto-configure services via their APIs.
Check off items as you go, or re-run \`./configure.sh\` to fill in the automated ones.

---

## Step 1 — Before starting
EOF

if $USE_VPN; then
cat >> "$TODO" <<EOF

- [ ] Place your VPN config at \`config/gluetun/vpn.ovpn\`
      For AirVPN: download an .ovpn from your AirVPN client area.
      For other providers: edit \`compose/vpn.yml\` → gluetun environment block.
      Verify after start: \`docker exec gluetun wget -qO- https://ifconfig.me\`
EOF
fi

cat >> "$TODO" <<EOF

- [ ] Start the stack: \`./start.sh\`

---

## Step 2 — Auto-configured by \`./configure.sh\`

Run this once the stack is up. It handles all of the below automatically:

- [ ] Extract API keys from Radarr, Sonarr, Prowlarr config files <!-- auto:api-keys -->
- [ ] Update \`.env\` with discovered API keys <!-- auto:env-update -->
- [ ] Add Radarr root folder (\`${RADARR_ROOT_FOLDER}\`) <!-- auto:radarr-rootfolder -->
- [ ] Add Sonarr root folder (\`${SONARR_ROOT_FOLDER}\`) <!-- auto:sonarr-rootfolder -->
- [ ] Connect Prowlarr → Radarr <!-- auto:prowlarr-radarr -->
- [ ] Connect Prowlarr → Sonarr <!-- auto:prowlarr-sonarr -->
EOF

if $USE_TORRENT; then
  DELUGE_HOST=$($USE_VPN && echo "gluetun" || echo "deluge")
cat >> "$TODO" <<EOF
- [ ] Add Deluge as download client in Radarr (host: \`${DELUGE_HOST}\`) <!-- auto:radarr-deluge -->
- [ ] Add Deluge as download client in Sonarr (host: \`${DELUGE_HOST}\`) <!-- auto:sonarr-deluge -->
EOF
fi

if $USE_USENET; then
cat >> "$TODO" <<EOF
- [ ] Extract SABnzbd API key and add as download client in Radarr <!-- auto:radarr-sabnzbd -->
- [ ] Extract SABnzbd API key and add as download client in Sonarr <!-- auto:sonarr-sabnzbd -->
EOF
fi

cat >> "$TODO" <<EOF
- [ ] Write Fetcharr config with Plex token + API keys <!-- auto:fetcharr-config -->
- [ ] Copy Tautulli scripts and patch credentials <!-- auto:tautulli-scripts -->
- [ ] Authenticate Trakt scrobbler (OAuth — interactive prompt) <!-- auto:tautulli-scrobbler -->
EOF

if $USE_TRAKT; then
cat >> "$TODO" <<EOF
- [ ] Restart Trakt containers with updated API keys <!-- auto:trakt-restart -->
EOF
fi

cat >> "$TODO" <<EOF

---

## Step 3 — Manual setup required

### Prowlarr — add indexers
- [ ] Open http://localhost:9696 → Indexers → Add Indexer
      Add your torrent/usenet indexers here.
      They sync automatically to Radarr and Sonarr — no manual setup needed there.
EOF

if $USE_USENET; then
cat >> "$TODO" <<EOF

### SABnzbd — add news server
- [ ] Open http://localhost:8085 → Config → Servers → Add Server
      Enter your Usenet provider credentials (host, port, username, password, SSL).
EOF
fi

cat >> "$TODO" <<EOF

### Radarr/Sonarr — quality profiles
- [ ] If you want a specific quality (e.g. \`1080p\`, \`4K\`), set it in Radarr/Sonarr:
      Settings → Profiles → create or edit a profile
- [ ] Then update \`.env\` to match:
      \`RADARR_QUALITY_PROFILE=1080p\`
      \`SONARR_QUALITY_PROFILE=1080p\`
      Re-run \`./configure.sh\` so Fetcharr picks up the new profile name.

### Plex — verify media libraries
- [ ] Open Plex at http://$(${USE_MACVLAN} && echo "${PLEX_LAN_IP}" || echo "localhost"):32400
      \`configure.sh\` creates both libraries automatically. If they are missing:
      Add movie library → folder: \`/media/movies\`
      Add TV library   → folder: \`/media/tv\`

### Tautulli — connect to Plex
- [ ] Open http://localhost:8181 → Settings → Plex Media Server
      - Plex IP or Hostname: \`plex\`  (the Docker container name — not \`localhost\`)
      - Plex Port: \`32400\`
      - Click **Verify Server** → then **Fetch New Token** → sign in → **Save**

### Tautulli — add notification agents
Both scripts are already in \`/scripts\` with credentials patched by \`configure.sh\`.
Open http://localhost:8181 → Settings → Notification Agents → **Add** → **Script**

#### Trakt Scrobbler
| Field | Value |
|---|---|
| Script Folder | \`/scripts\` |
| Script File | \`trakt_scrobbler.py\` |
| Script Timeout | \`30\` |

**Triggers:** Playback Start, Playback Stop, Playback Pause, Playback Resume

**Arguments** (paste the same line for every trigger):
\`\`\`
--action {action} --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id}
\`\`\`

#### Progressive Downloader
| Field | Value |
|---|---|
| Script Folder | \`/scripts\` |
| Script File | \`plex_progressive_downloader.py\` |
| Script Timeout | \`30\` |

**Triggers:** Playback Start only

**Conditions:** Media Type · is · episode

**Arguments** (Playback Start):
\`\`\`
-tvid {thetvdb_id} -sn {season_num} -en {episode_num}
\`\`\`

### Tautulli — scrobbler re-authentication
\`configure.sh\` handles this automatically on first run. If it failed or token expired:
- [ ] \`cd config/tautulli/scripts && python3 trakt_scrobbler.py --setup && cd -\`
      Run from the project root on the host (not inside Docker).
      Token saves to \`config/tautulli/scripts/trakt_tokens.json\`.
EOF

if $USE_TRAKT; then
cat >> "$TODO" <<EOF

### Trakt — watchlist sync OAuth
- [ ] \`configure.sh\` runs this automatically. If it failed or you need to re-authenticate:
      \`docker compose ${COMPOSE_FILES} run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup\`
      Visit the URL shown, enter the code, authorize. Then restart: \`./stop.sh && ./start.sh\`

### Trakt — cleanup webhooks
- [ ] Configured automatically by \`configure.sh\`. If missing, add manually:
      Radarr → Settings → Connect → Add → Webhook
      URL: \`http://trakt-watchlist-cleanup:5000/radarr\`  Trigger: On Movie Delete
      Sonarr → Settings → Connect → Add → Webhook
      URL: \`http://trakt-watchlist-cleanup:5000/sonarr\`  Trigger: On Series Delete
EOF
fi

if $USE_BAZARR; then
cat >> "$TODO" <<EOF

### Bazarr — subtitle providers
- [ ] Open http://localhost:6767 → Settings → Providers → add your subtitle sources
      (OpenSubtitles, Subscene, etc.)
- [ ] Settings → Languages → set your preferred language profile
EOF
fi

PLEX_URL="http://$(${USE_MACVLAN} && echo "${PLEX_LAN_IP}" || echo "localhost"):32400"
BAZARR_ROW=""
$USE_BAZARR && BAZARR_ROW="
| Bazarr | http://localhost:6767 |"
DELUGE_ROW=""
$USE_TORRENT && DELUGE_ROW="
| Deluge | http://localhost:8112 |"
SABNZBD_ROW=""
$USE_USENET && SABNZBD_ROW="
| SABnzbd | http://localhost:8085 |"

cat >> "$TODO" <<EOF

---

## Quick reference

| Service | URL |
|---|---|
| Plex | ${PLEX_URL} |
| Radarr | http://localhost:7878 |
| Sonarr | http://localhost:8989 |
| Prowlarr | http://localhost:9696 |
| Tautulli | http://localhost:8181 |${BAZARR_ROW}${DELUGE_ROW}${SABNZBD_ROW}

\`\`\`
./start.sh            # start everything
./stop.sh             # stop everything
./configure.sh        # auto-configure after first start
docker compose logs -f <service>   # view logs
\`\`\`
EOF

ok "TODO.md written"

# ─── Final message ────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Done!${RESET}"
echo ""
echo -e "  1. $(${USE_VPN} && echo "Place VPN config at config/gluetun/vpn.ovpn, then " || true)Run ${BOLD}./start.sh${RESET}"
echo -e "  2. Run ${BOLD}./configure.sh${RESET} to auto-configure Radarr, Sonarr, Prowlarr + download clients"
echo -e "  3. Follow remaining steps in ${BOLD}TODO.md${RESET}"
echo ""
