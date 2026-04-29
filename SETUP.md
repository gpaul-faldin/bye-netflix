# Setup Guide

Run `./setup.sh` first — it handles directories, `.env`, and `start.sh` automatically.
This guide covers what comes after.

---

## Prerequisites

- Docker + Docker Compose v2
- Python 3 on the host (used by `configure.sh`)
- For VPN: a supported provider (AirVPN, Mullvad, ProtonVPN, NordVPN, etc.)
- For Trakt: a Trakt.tv account and API app

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
- `TODO.md` — a per-install checklist

---

## 2. Configure VPN (if enabled)

Place your VPN config file at `config/gluetun/vpn.ovpn` **before** running `start.sh`.
`start.sh` will refuse to start if the file is missing.

For **AirVPN**: download a `.ovpn` file from your AirVPN client area.

For **other providers**: edit `compose/vpn.yml` — the `gluetun` environment block supports
Mullvad, ProtonVPN, NordVPN, and more. See: https://github.com/qdm12/gluetun/wiki

Verify after startup:
```bash
docker exec gluetun wget -qO- https://ifconfig.me
# Should return a VPN IP, not your home IP
```

---

## 3. Start the stack

```bash
./start.sh
```

---

## 4. Get a Plex claim token (first run only)

If you left `PLEX_CLAIM` blank during setup, get a token now:

1. Go to https://www.plex.tv/claim (expires in 4 minutes)
2. Add it to `.env` → `PLEX_CLAIM=claim-xxxxx`
3. Restart Plex: `docker compose restart plex`

Only needed once to link the server to your Plex account.

---

## 5. Run configure.sh

`configure.sh` automatically configures everything it can without human interaction.
Run it once the stack is up:

```bash
./configure.sh
```

It is safe to re-run — it checks for existing config before adding anything.

### What it does

| Step | What gets configured |
|---|---|
| API keys | Reads keys from each service's `config.xml` / INI, saves to `.env` |
| Root folders | Sets `/media/movies` and `/media/tv` in Radarr and Sonarr |
| Prowlarr sync | Connects Prowlarr → Radarr and Sonarr (full sync) |
| Deluge | Enables Labels plugin, creates `radarr`/`sonarr` labels, adds client to Radarr + Sonarr |
| SABnzbd | Patches hostname whitelist, creates `movies`/`tv` categories, adds client to Radarr + Sonarr |
| Fetcharr | Reads Plex token from `Preferences.xml`, writes `config/fetcharr/fetcharr.yaml` |
| Tautulli scripts | Copies scripts to `/scripts`, patches all credentials in-place |
| Bazarr | Connects Bazarr to Radarr and Sonarr via Bazarr API |
| Trakt webhooks | Adds "on delete" webhooks in Radarr and Sonarr → `trakt-watchlist-cleanup` |
| Plex libraries | Creates Movies (`/media/movies`) and TV Shows (`/media/tv`) libraries |
| Trakt containers | Restarts with updated API keys |
| Trakt scrobbler OAuth | Pauses and walks you through device-code login for the scrobbler |

---

## 6. Manual steps remaining after configure.sh

### Prowlarr — add indexers

Open http://localhost:9696 → Indexers → Add Indexer

Add your torrent and/or usenet indexers here. They sync to Radarr and Sonarr
automatically — no manual setup needed there.

---

### SABnzbd — add your news server (usenet only)

Open http://localhost:8085 → Config → Servers → Add Server

Enter your Usenet provider credentials: hostname, port, username, password, SSL on/off.
Your provider's website will have these details.

---

### Quality profiles (optional)

By default everything uses `Any`. To change:

1. In **Radarr** → Settings → Profiles → create or edit a quality profile
2. In **Sonarr** → Settings → Profiles → same
3. Update `.env` to match the exact profile name:
   ```
   RADARR_QUALITY_PROFILE=1080p
   SONARR_QUALITY_PROFILE=1080p
   ```
4. Re-run `./configure.sh` so Fetcharr picks up the new profile name.

---

### Plex — verify media libraries

`configure.sh` creates both libraries automatically. If they don't appear:

- Open Plex → Settings → Libraries → Add Library
- **Movies** → folder: `/media/movies`
- **TV Shows** → folder: `/media/tv`

---

### Tautulli — connect to Plex

Open http://localhost:8181 → Settings → Plex Media Server

1. **Plex IP or Hostname** — type `plex` (the Docker container name, not `localhost`)
2. **Plex Port** — `32400`
3. Click **Verify Server** — it should detect your server
4. Scroll down to **Plex.tv Authentication** → click **Fetch New Token**
   - A plex.tv login opens — sign in and authorize Tautulli
5. Click **Save**

> Tautulli defaults to `127.0.0.1` which doesn't resolve across Docker containers.
> The container name `plex` is required.

---

### Tautulli — add notification agents

Two scripts are placed in `/scripts` by `configure.sh` with credentials already patched in.
You just need to wire them up in the Tautulli UI.

Open http://localhost:8181 → Settings → Notification Agents → **Add a new notification agent** → **Script**

#### Trakt Scrobbler

| Field | Value |
|---|---|
| Script Folder | `/scripts` |
| Script File | `trakt_scrobbler.py` |
| Script Timeout | `30` |
| Description | `Trakt Scrobbler` |

**Triggers** tab — enable: Playback Start, Playback Stop, Playback Pause, Playback Resume

**Arguments** tab — paste the same line for each enabled trigger:
```
--action {action} --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id}
```

Save.

#### Progressive Downloader

| Field | Value |
|---|---|
| Script Folder | `/scripts` |
| Script File | `plex_progressive_downloader.py` |
| Script Timeout | `30` |
| Description | `Progressive Downloader` |

**Triggers** tab — enable: Playback Start only

**Conditions** tab — add: `Media Type` `is` `episode`

**Arguments** tab — Playback Start:
```
-tvid {thetvdb_id} -sn {season_num} -en {episode_num}
```

Save.

---

### Trakt — OAuth flows

`configure.sh` handles the **watchlist sync** OAuth interactively — it pauses, prints a
URL and device code, and waits while you authorize in your browser.

The **scrobbler** OAuth also runs in `configure.sh` — it runs
`docker exec tautulli python /scripts/trakt_scrobbler.py --setup` which prints the same
device-code prompt. Make sure Tautulli is running before running `configure.sh`.

If re-authentication is ever needed:
```bash
# Scrobbler (run from the project root — must run on the host, not inside Docker)
cd config/tautulli/scripts && python3 trakt_scrobbler.py --setup && cd -

# Watchlist sync
docker compose -f docker-compose.yml -f compose/trakt.yml \
  run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup
```

---

### Bazarr — subtitle providers (if enabled)

`configure.sh` connects Bazarr to Radarr and Sonarr automatically.
The only thing left is adding your subtitle sources:

Open http://localhost:6767:
- Settings → Providers → add your subtitle sources (OpenSubtitles, Subscene, etc.)
- Settings → Languages → set your preferred language profile

---

## macvlan / Plex LAN IP

The macvlan module (`compose/macvlan.yml`) gives Plex a real LAN IP so local clients
connect directly without Docker port-forwarding. All values come from `.env` — set
them during `setup.sh` or edit `.env` manually.

The host machine itself cannot reach the macvlan IP by default. Access Plex from
another device on the LAN, or create a macvlan shim on the host:

```bash
ip link add macvlan0 link YOUR_INTERFACE type macvlan mode bridge
ip addr add 192.168.1.101/32 dev macvlan0  # any unused LAN IP, NOT the Plex one
ip link set macvlan0 up
ip route add 192.168.1.100/32 dev macvlan0  # route to Plex's LAN IP
```

---

## Updating

```bash
./stop.sh
docker compose pull
./start.sh
```

Config in `./config/` is preserved across updates.
