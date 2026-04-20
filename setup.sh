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

echo "Most people have a single drive or folder for their media."
echo "Advanced setups can separate primary library, overflow storage, and a fast download SSD."

MEDIA_DIR=$(prompt MEDIA_DIR "Primary media directory (movies/TV will live here)" "/srv/media")

STORAGE_DIR="$MEDIA_DIR"
if yes_no "Do you have a separate secondary storage drive (e.g. a large HDD for overflow)?"; then
  STORAGE_DIR=$(prompt STORAGE_DIR "Secondary storage path" "/mnt/storage")
fi

SSD_DIR="$MEDIA_DIR"
if yes_no "Do you have a fast SSD dedicated to active downloads (speeds up imports)?"; then
  SSD_DIR=$(prompt SSD_DIR "SSD path" "/mnt/ssd")
fi

DOWNLOADS_DIR=$(prompt DOWNLOADS_DIR "Completed downloads staging directory" "${MEDIA_DIR}/downloads")

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
STORAGE_DIR=${STORAGE_DIR}
SSD_DIR=${SSD_DIR}
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

cat > "${SCRIPT_DIR}/start.sh" <<EOF
#!/usr/bin/env bash
# Generated by setup.sh on $(date)
# Run this to start your stack.
cd "\$(dirname "\${BASH_SOURCE[0]}")"
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

DIRS="plex radarr sonarr prowlarr tautulli/config tautulli/scripts bazarr fetcharr trakt-watchlist-sync"
$USE_TORRENT && DIRS="$DIRS deluge"
$USE_USENET  && DIRS="$DIRS sabnzbd"
$USE_VPN     && DIRS="$DIRS gluetun"

for d in $DIRS; do
  mkdir -p "${SCRIPT_DIR}/config/$d"
done
ok "Config directories created under ./config/"

# ─── Create media directories ────────────────────────────────────────────────
mkdir -p "${MEDIA_DIR}/movies" "${MEDIA_DIR}/tv" "${DOWNLOADS_DIR}"
[[ "$STORAGE_DIR" != "$MEDIA_DIR" ]] && mkdir -p "${STORAGE_DIR}/movies" "${STORAGE_DIR}/tv"
[[ "$SSD_DIR"     != "$MEDIA_DIR" ]] && mkdir -p "${SSD_DIR}"
ok "Media directories created"

# ─── Next steps ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Next steps${RESET}"
echo -e "${BOLD}══════════════════════════════════════════${RESET}"

STEP=1

if $USE_VPN; then
  echo ""
  echo -e "${BOLD}${STEP}. Configure your VPN${RESET}"
  echo "   Place your .ovpn file at: ${SCRIPT_DIR}/config/gluetun/vpn.ovpn"
  echo "   (For non-OpenVPN providers, edit docker-compose.vpn.yml instead)"
  STEP=$((STEP+1))
fi

echo ""
echo -e "${BOLD}${STEP}. Start the stack${RESET}"
echo "   ./start.sh"
STEP=$((STEP+1))

echo ""
echo -e "${BOLD}${STEP}. Get API keys${RESET}"
echo "   After the stack starts, visit each app and copy its API key:"
echo "   Radarr  → http://localhost:7878 → Settings → General → API Key"
echo "   Sonarr  → http://localhost:8989 → Settings → General → API Key"
echo "   Then add them to .env (RADARR_API_KEY / SONARR_API_KEY)"
echo "   and restart: ./stop.sh && ./start.sh"
STEP=$((STEP+1))

echo ""
echo -e "${BOLD}${STEP}. Configure Prowlarr${RESET}"
echo "   http://localhost:9696 → Settings → Apps → add Radarr + Sonarr"
echo "   Then add your indexers — they'll sync automatically"
STEP=$((STEP+1))

if $USE_TORRENT; then
  DELUGE_HOST=$( $USE_VPN && echo "http://localhost:8112" || echo "http://localhost:8112" )
  echo ""
  echo -e "${BOLD}${STEP}. Add Deluge as a download client${RESET}"
  echo "   Radarr/Sonarr → Settings → Download Clients → Add → Deluge"
  echo "   Host: $( $USE_VPN && echo "gluetun" || echo "deluge" )  Port: 58846  Password: ${DELUGE_PASSWORD}"
  STEP=$((STEP+1))
fi

if $USE_USENET; then
  echo ""
  echo -e "${BOLD}${STEP}. Add SABnzbd as a download client${RESET}"
  echo "   Radarr/Sonarr → Settings → Download Clients → Add → SABnzbd"
  echo "   Host: sabnzbd  Port: 8080"
  echo "   Get SABnzbd API key from: http://localhost:8085 → Config → General"
  STEP=$((STEP+1))
fi

if $USE_TRAKT; then
  echo ""
  echo -e "${BOLD}${STEP}. Authenticate Trakt${RESET}"
  echo "   docker compose ${COMPOSE_FILES} run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup"
  echo "   Then restart: ./stop.sh && ./start.sh"
  echo ""
  echo "   For Trakt cleanup webhooks (removes items when deleted):"
  echo "   Radarr  → Settings → Connect → Webhook → http://trakt-watchlist-cleanup:5000/radarr  (On Movie Delete)"
  echo "   Sonarr  → Settings → Connect → Webhook → http://trakt-watchlist-cleanup:5000/sonarr  (On Series Delete)"
  STEP=$((STEP+1))
fi

echo ""
echo -e "${BOLD}${STEP}. Install Tautulli scripts (optional — for Trakt scrobbling and smart downloads)${RESET}"
echo "   See SETUP.md → Tautulli Scripts section"
STEP=$((STEP+1))

echo ""
echo -e "${BOLD}${STEP}. Connect Bazarr to Radarr + Sonarr${RESET}"
echo "   http://localhost:6767 → Settings → Radarr / Sonarr"
STEP=$((STEP+1))

echo ""
echo -e "${GREEN}${BOLD}Setup complete. Run ./start.sh when ready.${RESET}"
echo ""
