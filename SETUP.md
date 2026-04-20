# Setup Guide

Run `./setup.sh` first — it handles directories, `.env`, and `start.sh` automatically.
This guide covers what comes after.

---

## Prerequisites

- Docker + Docker Compose v2
- `git`
- For Tautulli scripts: Python 3 available inside the Tautulli container (it's pre-installed)
- For VPN: a supported provider (AirVPN, Mullvad, ProtonVPN, NordVPN, etc.)
- For Trakt: a Trakt.tv account

---

## 1. Run setup.sh

```bash
./setup.sh
```

Answer the prompts. At the end you'll have:
- `.env` — all your configuration
- `start.sh` / `stop.sh` — pre-built compose commands for your chosen modules
- `config/` subdirectories for each enabled service
- Your media directories created

Then start the stack:
```bash
./start.sh
```

---

## 2. Configure VPN (if enabled)

Place your VPN config file at `config/gluetun/vpn.ovpn`.

For **AirVPN**: download a `.ovpn` file from your AirVPN client area.

For **other providers**: edit `compose/vpn.yml` — the `gluetun` service environment block supports Mullvad, ProtonVPN, NordVPN, and more. See: https://github.com/qdm12/gluetun/wiki

Verify after startup:
```bash
docker exec gluetun wget -qO- https://ifconfig.me
# Should return a VPN IP, not your home IP
```

---

## 3. Get Plex claim token

If you set `PLEX_CLAIM` blank during setup, get a token now:

1. Go to https://www.plex.tv/claim (token expires in 4 minutes)
2. Add it to `.env` → `PLEX_CLAIM=claim-xxxxx`
3. Restart Plex: `docker compose restart plex`

Only needed on first run to link the server to your Plex account.

---

## 4. Configure Prowlarr

1. Open http://localhost:9696
2. Settings → Apps → Add Radarr (URL: `http://radarr:7878`, API key from step 5)
3. Settings → Apps → Add Sonarr (URL: `http://sonarr:8989`, API key from step 5)
4. Indexers → Add your indexers — they sync automatically to Radarr and Sonarr

---

## 5. Get API keys and update .env

After first run, grab API keys from each service:

- Radarr: http://localhost:7878 → Settings → General → API Key
- Sonarr: http://localhost:8989 → Settings → General → API Key

Add them to `.env`:
```
RADARR_API_KEY=your_key_here
SONARR_API_KEY=your_key_here
```

Restart: `./stop.sh && ./start.sh`

---

## 6. Configure download clients in Radarr & Sonarr

**Deluge (torrents):**

Settings → Download Clients → Add → Deluge
- Host: `gluetun` (if using VPN) or `deluge` (if no VPN)
- Port: `58846`
- Password: value of `DELUGE_PASSWORD` in `.env`

**SABnzbd (usenet):**

Settings → Download Clients → Add → SABnzbd
- Host: `sabnzbd`
- Port: `8080`
- API Key: get from http://localhost:8085 → Config → General

**Root folders** (Settings → Media Management → Root Folders):
- Radarr: `/media/movies` (or your `RADARR_ROOT_FOLDER` value)
- Sonarr: `/media/tv` (or your `SONARR_ROOT_FOLDER` value)

---

## 7. Authenticate Trakt (if enabled)

```bash
docker compose -f docker-compose.yml -f compose/trakt.yml \
  run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup
```

Follow the instructions: visit the URL, enter the code, authorize. Token saves to `config/trakt-watchlist-sync/trakt_tokens.json`.

Restart: `./stop.sh && ./start.sh`

**Cleanup webhooks** (removes items from Trakt when deleted locally):

In Radarr → Settings → Connect → Add → Webhook:
- URL: `http://trakt-watchlist-cleanup:5000/radarr`
- Trigger: `On Movie Delete`

In Sonarr → Settings → Connect → Add → Webhook:
- URL: `http://trakt-watchlist-cleanup:5000/sonarr`
- Trigger: `On Series Delete`

---

## 8. Tautulli scripts

These scripts run inside Tautulli as notification agents.

### Install

```bash
cp tautulliScripts/trakt_scrobbler.py config/tautulli/scripts/
cp tautulliScripts/plex_progressive_downloader.py config/tautulli/scripts/
```

### Update credentials

**`trakt_scrobbler.py`** — edit these constants at the top of the file:
```python
TRAKT_CLIENT_ID     = "your_trakt_client_id"
TRAKT_CLIENT_SECRET = "your_trakt_client_secret"
TAUTULLI_API_KEY    = "your_tautulli_api_key"
# Tautulli API key: Settings → Web Interface → API key
```

**`plex_progressive_downloader.py`** — edit:
```python
SONARR_APIKEY = "your_sonarr_api_key"
```

### Authenticate scrobbler

```bash
docker exec -it tautulli python /scripts/trakt_scrobbler.py --setup
```

Follow the OAuth flow. Token saves to `/scripts/trakt_tokens.json`.

### Set up notification agents in Tautulli

**Trakt Scrobbler** (tracks play/pause/stop):

Settings → Notification Agents → Add → Script
- Script folder: `/scripts`
- Script file: `trakt_scrobbler.py`
- Triggers: Playback Start, Playback Stop, Playback Pause, Playback Resume
- Arguments for each trigger:
  ```
  --action {action} --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id}
  ```

**Progressive Downloader** (pre-fetches upcoming episodes):

Settings → Notification Agents → Add → Script
- Script folder: `/scripts`
- Script file: `plex_progressive_downloader.py`
- Trigger: Playback Start (filter: Media Type = `episode`)
- Arguments:
  ```
  -tvid {thetvdb_id} -sn {season_num} -en {episode_num}
  ```

---

## 9. Connect Tautulli to Plex

Settings → Plex Media Server
- Plex IP: `plex` (Docker DNS) or your macvlan LAN IP
- Port: `32400`
- Authenticate with your Plex token

---

## 10. Configure Fetcharr

Fetcharr monitors your Plex watchlist and sends items to Radarr/Sonarr.

Edit `config/fetcharr/config.yml` (generated on first run):
```yaml
radarr:
  - url: http://radarr:7878
    apiKey: your_radarr_api_key
    rootFolder: /media/movies

sonarr:
  - url: http://sonarr:8989
    apiKey: your_sonarr_api_key
    rootFolder: /media/tv
```

Fetcharr also needs a Plex token to read your watchlist — configure this in the Fetcharr UI at http://localhost:8080.

---

## 11. Configure Bazarr

http://localhost:6767

- Settings → Sonarr: URL `http://sonarr:8989`, API key
- Settings → Radarr: URL `http://radarr:7878`, API key
- Settings → Providers: add subtitle providers (OpenSubtitles, etc.)
- Settings → Languages: set your language profile

---

## macvlan / Plex LAN IP

The macvlan module (`compose/macvlan.yml`) gives Plex a real LAN IP so local clients connect directly without Docker port-forwarding. All values come from `.env` — set them during `setup.sh` or edit `.env` manually.

The host machine itself cannot reach the macvlan IP by default. Access Plex from another device, or create a macvlan shim interface on the host:
```bash
ip link add macvlan0 link YOUR_INTERFACE type macvlan mode bridge
ip addr add 192.168.1.101/32 dev macvlan0  # any unused LAN IP, NOT the Plex one
ip link set macvlan0 up
ip route add 192.168.1.100/32 dev macvlan0  # route to Plex's IP
```

---

## Updating

```bash
./stop.sh
docker compose pull   # pull latest images
./start.sh
```

Config in `./config/` is preserved across updates.
