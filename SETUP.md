# ReplaceNetflix - Complete Setup Guide

A complete media automation stack using Plex, Radarr, Sonarr, Deluge, and Trakt integration.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Configuration](#detailed-configuration)
  - [Environment Variables](#environment-variables)
  - [Plex Configuration](#plex-configuration)
  - [YggTorrent Configuration](#yggtorrent-configuration)
  - [Tautulli Scripts Configuration](#tautulli-scripts-configuration)
  - [Trakt Integration Configuration](#trakt-integration-configuration)
  - [Fetcharr Configuration](#fetcharr-configuration)
- [First-Time Setup](#first-time-setup)
- [Service Configuration](#service-configuration)
- [Webhook Setup](#webhook-setup)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Docker & Docker Compose installed
- A Trakt.tv account (free) - [Sign up here](https://trakt.tv/auth/signup)
- A Plex account - [Sign up here](https://www.plex.tv/sign-up/)
- A YggTorrent account (if using French content)
- Basic understanding of Linux file permissions (PUID/PGID)

---

## Quick Start

```bash
# 1. Clone the repository
git clone <repository-url>
cd ReplaceNetflix

# 2. Set up your media directories (adjust MEDIA_DIR in .env if needed)
# Default: /srv
sudo mkdir -p /srv/{downloads/complete,downloads/incomplete,movies,tv}
sudo chown -R 1000:1000 /srv

# 3. Configure required settings (see Detailed Configuration section)
# Edit these files:
# - .env (if changing media directory)
# - docker-compose.yml (Plex claim token, Trakt credentials, API keys)
# - config/ygege/config.json (YggTorrent credentials)
# - tautulliScripts/trakt_scrobbler.py (Trakt API credentials, Tautulli API key)
# - config/fetcharr/fetcharr.yaml (Plex token, API keys)

# 4. Start all services
docker compose up -d

# 5. Complete first-time setup (see First-Time Setup section)
```

---

## Detailed Configuration

### Environment Variables

#### `.env` file
```env
# Configurable media root on the host
# This is where all your media will be stored
MEDIA_DIR=/srv
```

**What to modify:**
- Change `MEDIA_DIR` if you want to use a different directory for your media
- Make sure the directory exists and has proper permissions (owned by user 1000:1000)

---

### Plex Configuration

#### In `docker-compose.yml` - Plex Service

```yaml
plex:
  environment:
    - PUID=1000                          # Change if your user ID is different
    - PGID=1000                          # Change if your group ID is different
    - TZ=Europe/Paris                    # Change to your timezone
    - PLEX_CLAIM=claim-1Cfz414fZn5kX7tpm2Hq  # ⚠️ CHANGE THIS!
```

**What to modify:**

1. **PLEX_CLAIM** (Required for first setup):
   - Go to https://www.plex.tv/claim/
   - Copy the claim token (starts with `claim-`)
   - Replace the value in docker-compose.yml
   - This token expires in 4 minutes, so start the container right after!

2. **TZ** (Timezone):
   - Find your timezone: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
   - Examples: `America/New_York`, `Europe/London`, `Asia/Tokyo`

3. **PUID/PGID** (User/Group ID):
   - Find your user ID: `id -u`
   - Find your group ID: `id -g`
   - Update if different from 1000

---

### YggTorrent Configuration

#### In `config/ygege/config.json`

```json
{
    "username": "YOUR_YGG_USERNAME",     # ⚠️ CHANGE THIS!
    "password": "YOUR_YGG_PASSWORD",     # ⚠️ CHANGE THIS!
    "bind_ip": "0.0.0.0",
    "bind_port": 8715,
    "log_level": "debug"
}
```

**What to modify:**
- Replace `YOUR_YGG_USERNAME` with your YggTorrent username
- Replace `YOUR_YGG_PASSWORD` with your YggTorrent password
- Keep other settings as-is unless you know what you're doing

**Note:** If you don't use YggTorrent, you can disable this service by commenting it out in docker-compose.yml

---

### Tautulli Scripts Configuration

#### In `tautulliScripts/trakt_scrobbler.py`

```python
# ## CONFIGURATION - EDIT THESE SETTINGS ##
TRAKT_CLIENT_ID = 'YOUR_CLIENT_ID'           # ⚠️ CHANGE THIS!
TRAKT_CLIENT_SECRET = 'YOUR_CLIENT_SECRET'   # ⚠️ CHANGE THIS!
TRAKT_REDIRECT_URI = 'urn:ietf:wg:oauth:2.0:oob'

# Tautulli API configuration
TAUTULLI_URL = 'http://tautulli:8181'
TAUTULLI_API_KEY = 'YOUR_TAUTULLI_API_KEY'  # ⚠️ WILL BE CONFIGURED LATER!

# File to store access tokens
TOKEN_FILE = './trakt_tokens.json'           # ⚠️ CHANGE THIS TO AN ABSOLUTE PATH!
```

**What to modify:**

1. **Trakt API Credentials** (Before starting):
   - Go to https://trakt.tv/oauth/applications/new
   - Create a new application:
     - Name: `Tautulli Scrobbler` (or any name)
     - Redirect URI: `urn:ietf:wg:oauth:2.0:oob`
   - Copy the **Client ID** and **Client Secret**
   - Replace in the script

2. **TOKEN_FILE** (Important):
   - Change from `./trakt_tokens.json` to an absolute path
   - Example: `/config/trakt_tokens.json`
   - This ensures tokens persist between script runs

3. **TAUTULLI_API_KEY** (After Tautulli setup):
   - Will be configured during first-time setup
   - Get from Tautulli Settings → Web Interface → API Key

**Copy script to Tautulli container:**
After modifying, the script is mounted into Tautulli at `/scripts/trakt_scrobbler.py`

---

### Trakt Integration Configuration

#### In `docker-compose.yml` - Trakt Services

```yaml
trakt-watchlist-sync:
  environment:
    - TRAKT_CLIENT_ID=YOUR_CLIENT_ID              # ⚠️ CHANGE THIS!
    - TRAKT_CLIENT_SECRET=YOUR_CLIENT_SECRET      # ⚠️ CHANGE THIS!
    - RADARR_URL=http://radarr:7878
    - RADARR_API_KEY=WILL_BE_CONFIGURED_LATER     # ⚠️ WILL BE CONFIGURED LATER!
    - RADARR_ROOT_FOLDER=/srv/movies/
    - RADARR_QUALITY_PROFILE=Any
    - SONARR_URL=http://sonarr:8989
    - SONARR_API_KEY=WILL_BE_CONFIGURED_LATER     # ⚠️ WILL BE CONFIGURED LATER!
    - SONARR_ROOT_FOLDER=/srv/tv/
    - SONARR_QUALITY_PROFILE=Any
    - POLL_INTERVAL=20                             # Check watchlist every 20 seconds

trakt-watchlist-cleanup:
  environment:
    - TRAKT_CLIENT_ID=YOUR_CLIENT_ID              # ⚠️ CHANGE THIS!
    - TRAKT_CLIENT_SECRET=YOUR_CLIENT_SECRET      # ⚠️ CHANGE THIS!
```

**What to modify:**

1. **Trakt API Credentials** (Before starting):
   - Use the SAME credentials as the Tautulli scrobbler
   - Or create a new app at https://trakt.tv/oauth/applications/new

2. **RADARR_API_KEY / SONARR_API_KEY** (After setup):
   - Will be configured during first-time setup
   - Get from Radarr/Sonarr Settings → General → Security → API Key

3. **POLL_INTERVAL**:
   - How often to check Trakt watchlist (in seconds)
   - Default: 20 seconds (very responsive)
   - Increase to reduce API calls: 60 (1 min), 300 (5 min), 600 (10 min)

4. **Root Folders**:
   - Change if you modified MEDIA_DIR in .env
   - Must match the actual paths in your system

5. **Quality Profiles**:
   - Default: "Any" (downloads any quality)
   - Change to match your Radarr/Sonarr quality profile names
   - Examples: "HD-1080p", "Ultra-HD", "SD"

---

### Fetcharr Configuration

#### In `config/fetcharr/fetcharr.yaml`

```yaml
plex:
  api_token: YOUR_PLEX_TOKEN_HERE               # ⚠️ CHANGE THIS!
  sync_friends_watchlist: false

sonarr:
  default:
    enabled: true
    base_url: http://sonarr:8989
    api_key: WILL_BE_CONFIGURED_LATER           # ⚠️ WILL BE CONFIGURED LATER!
    root_folder: /tv                            # Relative to /srv
    monitored: true
    search_immediately: true

radarr:
  default:
    enabled: true
    base_url: http://radarr:7878
    api_key: WILL_BE_CONFIGURED_LATER           # ⚠️ WILL BE CONFIGURED LATER!
    root_folder: /movies                        # Relative to /srv
    monitored: true
    search_immediately: true
```

**What to modify:**

1. **Plex API Token** (Before starting):
   - Go to https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/
   - Follow the guide to get your token
   - Replace `YOUR_PLEX_TOKEN_HERE` with your token

2. **Sonarr/Radarr API Keys** (After setup):
   - Will be configured during first-time setup
   - Get from Radarr/Sonarr Settings → General → Security → API Key

3. **Root Folders**:
   - Paths are relative to /srv (not absolute paths)
   - Default: `/tv` for shows, `/movies` for movies
   - Change if you have a different structure

---

## First-Time Setup

### 1. Start All Services

```bash
docker compose up -d
```

Wait 30 seconds for all services to initialize.

### 2. Verify Services Are Running

```bash
docker compose ps
```

All services should show "Up" status.

### 3. Configure Services (In Order)

#### A. Plex (Port 32400)
1. Access: http://localhost:32400/web
2. Complete the initial setup wizard
3. Add libraries:
   - Movies: `/srv/movies`
   - TV Shows: `/srv/tv`

#### B. Prowlarr (Port 9696)
1. Access: http://localhost:9696
2. Complete initial setup
3. Add indexers:
   - YggTorrent (via ygege proxy): http://ygege:8715
   - Add other indexers as needed
4. Settings → Apps → Add Radarr:
   - Name: Radarr
   - Prowlarr Server: http://prowlarr:9696
   - Radarr Server: http://radarr:7878
   - API Key: Get from Radarr (see below)
5. Settings → Apps → Add Sonarr:
   - Name: Sonarr
   - Prowlarr Server: http://prowlarr:9696
   - Sonarr Server: http://sonarr:8989
   - API Key: Get from Sonarr (see below)

#### C. Deluge (Port 8112)
1. Access: http://localhost:8112
2. Default password: `deluge`
3. Change password: Preferences → Interface → Password
4. Configure downloads:
   - Download to: `/srv/downloads/incomplete`
   - Move completed to: `/srv/downloads/complete`

#### D. Radarr (Port 7878)
1. Access: http://localhost:7878
2. Complete initial setup
3. Get API Key:
   - Settings → General → Security → API Key
   - **Copy this key** - you'll need it for:
     - Prowlarr connection
     - Fetcharr configuration
     - Trakt sync configuration
4. Settings → Media Management:
   - Root Folders: Add `/srv/movies`
   - Movie Naming: Configure to your preference
5. Settings → Download Clients → Add Deluge:
   - Host: `deluge`
   - Port: `58846`
   - Password: Your Deluge password
   - Category: `radarr`

#### E. Sonarr (Port 8989)
1. Access: http://localhost:8989
2. Complete initial setup
3. Get API Key:
   - Settings → General → Security → API Key
   - **Copy this key** - you'll need it for:
     - Prowlarr connection
     - Fetcharr configuration
     - Trakt sync configuration
4. Settings → Media Management:
   - Root Folders: Add `/srv/tv`
   - Episode Naming: Configure to your preference
5. Settings → Download Clients → Add Deluge:
   - Host: `deluge`
   - Port: `58846`
   - Password: Your Deluge password
   - Category: `sonarr`

#### F. Bazarr (Port 6767)
1. Access: http://localhost:6767
2. Complete initial setup
3. Languages → Add languages you want subtitles for
4. Settings → Sonarr:
   - Address: `http://sonarr`
   - Port: `8989`
   - API Key: Your Sonarr API key
5. Settings → Radarr:
   - Address: `http://radarr`
   - Port: `7878`
   - API Key: Your Radarr API key

#### G. Tautulli (Port 8181)
1. Access: http://localhost:8181
2. Complete initial setup
3. Connect to Plex server
4. Get API Key:
   - Settings → Web Interface → API Key
   - **Copy this key** - you'll need it for Trakt scrobbler
5. Configure Trakt Scrobbler (see Tautulli Scripts section)

#### H. Overseerr (Port 5055) - Optional
1. Access: http://localhost:5055
2. Complete initial setup
3. Connect to Plex
4. Connect to Radarr and Sonarr with their API keys

### 4. Update Configuration Files

Now that you have all the API keys, update these files:

#### A. Update `docker-compose.yml`
```yaml
# Replace these values:
- RADARR_API_KEY=<your_radarr_api_key>
- SONARR_API_KEY=<your_sonarr_api_key>
```

#### B. Update `tautulliScripts/trakt_scrobbler.py`
```python
TAUTULLI_API_KEY = '<your_tautulli_api_key>'
```

#### C. Update `config/fetcharr/fetcharr.yaml`
```yaml
sonarr:
  default:
    api_key: <your_sonarr_api_key>

radarr:
  default:
    api_key: <your_radarr_api_key>
```

### 5. Restart Services to Apply Configuration

```bash
docker compose down
docker compose up -d
```

### 6. Authenticate Trakt Services

#### A. Authenticate Trakt Watchlist Sync
```bash
docker compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup
```

Follow the prompts:
1. Visit the URL shown
2. Enter the code displayed
3. Authorize the application
4. Wait for confirmation

#### B. Authenticate Trakt Scrobbler (Tautulli)
```bash
# Access the Tautulli container
docker exec -it tautulli bash

# Navigate to scripts directory
cd /scripts

# Run setup
python3 trakt_scrobbler.py --setup

# Follow the prompts as above

# Test the connection
python3 trakt_scrobbler.py --test

# Exit container
exit
```

---

## Service Configuration

### Tautulli Trakt Scrobbler Setup

After authenticating, configure the script in Tautulli:

1. **Tautulli → Settings → Notification Agents → Add a new notification agent → Script**

2. **Configuration Tab:**
   - Script Folder: `/scripts`
   - Script File: `./trakt_scrobbler.py`
   - Description: `Trakt Scrobbler`

3. **Triggers Tab:**
   - Enable: ✓ Playback Start
   - Enable: ✓ Playback Stop
   - Enable: ✓ Playback Pause
   - Enable: ✓ Playback Resume

4. **Conditions Tab:**
   - Condition: Media Type
   - Operator: is
   - Value: movie, episode

5. **Arguments Tab:**
   - Playback Start:
     ```
     --action play --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id} --session_id {session_id} --rating_key {rating_key}
     ```
   
   - Playback Stop:
     ```
     --action stop --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id}
     ```
   
   - Playback Pause:
     ```
     --action pause --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id}
     ```
   
   - Playback Resume:
     ```
     --action resume --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id} --session_id {session_id} --rating_key {rating_key}
     ```

6. **Save** and **Test** the script

---

## Webhook Setup

### Radarr Webhook (For Trakt Cleanup)

1. Radarr → Settings → Connect → Add → Webhook
2. Configure:
   - Name: `Trakt Cleanup`
   - On Delete: ✓ Enabled
   - URL: `http://trakt-watchlist-cleanup:5000/radarr`
   - Method: POST
3. Save

### Sonarr Webhook (For Trakt Cleanup)

1. Sonarr → Settings → Connect → Add → Webhook
2. Configure:
   - Name: `Trakt Cleanup`
   - On Series Delete: ✓ Enabled
   - URL: `http://trakt-watchlist-cleanup:5000/sonarr`
   - Method: POST
3. Save

---

## Usage

### Managing Services

Use the provided management script:

```bash
# Start all services
./manage.sh start

# Stop all services
./manage.sh stop

# Restart all services
./manage.sh restart

# Update all services
./manage.sh update

# View logs (all services)
./manage.sh logs

# View logs (specific service)
./manage.sh logs plex
./manage.sh logs radarr
./manage.sh logs sonarr

# Check service status
./manage.sh status
```

### Using Trakt Watchlist

1. **Add content to your Trakt watchlist:**
   - Use the Trakt website or mobile app
   - Add movies or TV shows to your watchlist

2. **Automatic download:**
   - The sync service checks every 20 seconds (configurable)
   - New items are automatically added to Radarr/Sonarr
   - Radarr/Sonarr will search for and download the content
   - Downloaded content appears in Plex automatically

3. **Automatic cleanup:**
   - When you delete a movie/show from Radarr/Sonarr
   - It's automatically removed from your Trakt watchlist

### Using Plex Watchlist (via Fetcharr)

1. **Add content to your Plex watchlist:**
   - Use the Plex website or mobile app
   - Add movies or TV shows to your watchlist

2. **Automatic download:**
   - Fetcharr monitors your Plex watchlist
   - New items are automatically added to Radarr/Sonarr
   - Content is downloaded and appears in Plex

### Trakt Scrobbling

- **Automatic:** When you watch content in Plex
  - Watch progress is sent to Trakt
  - Items are marked as "watched" when you finish them (80%+ progress)
  - Your Trakt profile stays in sync with your viewing

---

## Troubleshooting

### Services Not Starting

```bash
# Check service status
docker compose ps

# View logs for problematic service
docker compose logs <service-name>

# Example:
docker compose logs plex
docker compose logs radarr
```

### Plex Not Connecting

1. Check if claim token is valid (expires in 4 minutes)
2. Get a new claim token: https://www.plex.tv/claim/
3. Update docker-compose.yml
4. Restart: `docker compose restart plex`

### Trakt Authentication Failing

1. Check if Client ID and Secret are correct
2. Make sure Redirect URI is: `urn:ietf:wg:oauth:2.0:oob`
3. Re-run authentication:
   ```bash
   docker compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup
   ```

### Prowlarr Not Finding Indexers

1. Check if ygege container is running: `docker compose ps ygege`
2. Check ygege logs: `docker compose logs ygege`
3. Verify YggTorrent credentials in `config/ygege/config.json`

### Downloads Not Starting

1. Check Prowlarr → Indexers (are they working?)
2. Check Radarr/Sonarr → System → Logs
3. Check Deluge is connected:
   - Radarr/Sonarr → Settings → Download Clients → Test
4. Check Deluge credentials match

### Trakt Scrobbler Not Working

1. Check Tautulli logs: `docker compose logs tautulli`
2. Test the script manually:
   ```bash
   docker exec -it tautulli python3 /scripts/trakt_scrobbler.py --test
   ```
3. Check script configuration in Tautulli → Settings → Notification Agents

### Permission Issues

If you encounter permission errors:

```bash
# Fix permissions for media directories
sudo chown -R 1000:1000 /srv

# Fix permissions for config directories
sudo chown -R 1000:1000 ./config
```

### Ports Already in Use

If a port is already in use:

1. Find what's using it: `sudo netstat -tulpn | grep :<port>`
2. Stop the conflicting service
3. Or change the port in docker-compose.yml:
   ```yaml
   ports:
     - "NEW_PORT:CONTAINER_PORT"
   ```

### Checking Container Health

```bash
# View all container stats
docker stats

# Enter a container for debugging
docker exec -it <container-name> bash

# Example:
docker exec -it radarr bash
docker exec -it sonarr bash
```

---

## Advanced Configuration

### Enable VPN (Optional)

To route download traffic through a VPN:

1. Uncomment the `gluetun` service in docker-compose.yml
2. Configure your VPN provider:
   ```yaml
   gluetun:
     environment:
       - VPN_SERVICE_PROVIDER=nordvpn  # Change to your provider
       - VPN_TYPE=openvpn
       - OPENVPN_USER=your_username
       - OPENVPN_PASSWORD=your_password
   ```
3. Update deluge service:
   ```yaml
   deluge:
     network_mode: "service:gluetun"
     depends_on:
       - gluetun
     # Remove the ports section
   ```
4. Restart services

### Changing Media Directories

To use a different location for media:

1. Update `.env`:
   ```env
   MEDIA_DIR=/your/custom/path
   ```

2. Update docker-compose.yml root folders:
   ```yaml
   - RADARR_ROOT_FOLDER=/your/custom/path/movies/
   - SONARR_ROOT_FOLDER=/your/custom/path/tv/
   ```

3. Create directories:
   ```bash
   sudo mkdir -p /your/custom/path/{downloads/complete,downloads/incomplete,movies,tv}
   sudo chown -R 1000:1000 /your/custom/path
   ```

4. Restart services

---

## Security Notes

- **API Keys:** Keep your API keys private. Don't commit them to public repositories.
- **Passwords:** Change default passwords (Deluge, etc.)
- **Network:** Consider using a reverse proxy (Nginx, Traefik) for HTTPS
- **Firewall:** Only expose necessary ports to the internet
- **VPN:** Consider using a VPN for torrent traffic

---

## Support

For issues and questions:
- Check logs: `docker compose logs <service>`
- Review Troubleshooting section above
- Check service-specific documentation

---

## Credits

Services used:
- [Plex](https://www.plex.tv/)
- [Radarr](https://radarr.video/)
- [Sonarr](https://sonarr.tv/)
- [Prowlarr](https://prowlarr.com/)
- [Deluge](https://deluge-torrent.org/)
- [Bazarr](https://www.bazarr.media/)
- [Tautulli](https://tautulli.com/)
- [Overseerr](https://overseerr.dev/)
- [Fetcharr](https://github.com/Fetcharr/Fetcharr)
- [Trakt.tv](https://trakt.tv/)
