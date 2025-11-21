# ReplaceNetflix - Setup Checklist

Quick reference checklist to set up the media automation stack.

## ✅ Pre-Setup Checklist

### Accounts to Create (Before Starting)
- [ ] Trakt.tv account → https://trakt.tv/auth/signup
- [ ] Plex account → https://www.plex.tv/sign-up/
- [ ] YggTorrent account (if using French content)

### Trakt API Application
- [ ] Go to https://trakt.tv/oauth/applications/new
- [ ] Create application:
  - Name: `Media Automation` (or any name)
  - Redirect URI: `urn:ietf:wg:oauth:2.0:oob`
- [ ] Save **Client ID**: `______________________________`
- [ ] Save **Client Secret**: `______________________________`

### Plex Configuration
- [ ] Get Plex Claim Token → https://www.plex.tv/claim/
- [ ] Token (expires in 4 min): `______________________________`
- [ ] Get Plex API Token → https://support.plex.tv/articles/204059436/
- [ ] API Token: `______________________________`

---

## 🔧 Configuration Files Checklist

### 1. `.env` (Optional - only if changing media directory)
```env
MEDIA_DIR=/srv  # Change if needed
```
- [ ] Configured

### 2. `docker-compose.yml` (Required)

**Plex Service:**
```yaml
- PLEX_CLAIM=_______________  # Your claim token
- TZ=_______________          # Your timezone (e.g., Europe/Paris)
```
- [ ] PLEX_CLAIM updated
- [ ] TZ updated

**Trakt Services (2 locations):**
```yaml
trakt-watchlist-sync:
  environment:
    - TRAKT_CLIENT_ID=_______________      # From Trakt app
    - TRAKT_CLIENT_SECRET=_______________  # From Trakt app
    - RADARR_API_KEY=_______________       # Get after Radarr setup
    - SONARR_API_KEY=_______________       # Get after Sonarr setup

trakt-watchlist-cleanup:
  environment:
    - TRAKT_CLIENT_ID=_______________      # Same as above
    - TRAKT_CLIENT_SECRET=_______________  # Same as above
```
- [ ] TRAKT_CLIENT_ID updated (both services)
- [ ] TRAKT_CLIENT_SECRET updated (both services)
- [ ] RADARR_API_KEY updated (will do after setup)
- [ ] SONARR_API_KEY updated (will do after setup)

### 3. `config/ygege/config.json` (Required if using YggTorrent)
```json
{
    "username": "_______________",
    "password": "_______________",
    "bind_ip": "0.0.0.0",
    "bind_port": 8715,
    "log_level": "debug"
}
```
- [ ] Username updated
- [ ] Password updated

### 4. `tautulliScripts/trakt_scrobbler.py` (Required)
```python
TRAKT_CLIENT_ID = '_______________'
TRAKT_CLIENT_SECRET = '_______________'
TAUTULLI_API_KEY = '_______________'  # Get after Tautulli setup
TOKEN_FILE = '/config/trakt_tokens.json'  # Must be absolute path!
```
- [ ] TRAKT_CLIENT_ID updated
- [ ] TRAKT_CLIENT_SECRET updated
- [ ] TOKEN_FILE changed to absolute path
- [ ] TAUTULLI_API_KEY updated (will do after setup)

### 5. `config/fetcharr/fetcharr.yaml` (Required)
```yaml
plex:
  api_token: _______________  # Your Plex API token

sonarr:
  default:
    api_key: _______________  # Get after Sonarr setup

radarr:
  default:
    api_key: _______________  # Get after Radarr setup
```
- [ ] Plex api_token updated
- [ ] Sonarr api_key updated (will do after setup)
- [ ] Radarr api_key updated (will do after setup)

---

## 🚀 Installation & First Start

### Media Directories Setup
```bash
sudo mkdir -p /srv/{downloads/complete,downloads/incomplete,movies,tv}
sudo chown -R 1000:1000 /srv
```
- [ ] Directories created
- [ ] Permissions set

### Start Services
```bash
docker compose up -d
```
- [ ] All services started
- [ ] Waited 30 seconds for initialization
- [ ] Verified status: `docker compose ps`

---

## ⚙️ Service Configuration (Do in Order)

### 1. Plex (http://localhost:32400/web)
- [ ] Completed setup wizard
- [ ] Added Movies library: `/srv/movies`
- [ ] Added TV Shows library: `/srv/tv`

### 2. Deluge (http://localhost:8112)
- [ ] Logged in (password: `deluge`)
- [ ] Changed default password
- [ ] Saved new password: `_______________`
- [ ] Configured downloads:
  - Download to: `/srv/downloads/incomplete`
  - Move completed to: `/srv/downloads/complete`

### 3. Radarr (http://localhost:7878)
- [ ] Completed setup wizard
- [ ] Got API Key: `_______________`
- [ ] Added root folder: `/srv/movies`
- [ ] Added Deluge download client:
  - Host: `deluge`
  - Port: `58846`
  - Password: Your Deluge password
  - Category: `radarr`

### 4. Sonarr (http://localhost:8989)
- [ ] Completed setup wizard
- [ ] Got API Key: `_______________`
- [ ] Added root folder: `/srv/tv`
- [ ] Added Deluge download client:
  - Host: `deluge`
  - Port: `58846`
  - Password: Your Deluge password
  - Category: `sonarr`

### 5. Prowlarr (http://localhost:9696)
- [ ] Completed setup wizard
- [ ] Added YggTorrent indexer (via ygege): `http://ygege:8715`
- [ ] Added other indexers as needed
- [ ] Connected to Radarr:
  - Radarr Server: `http://radarr:7878`
  - API Key: Your Radarr API key
- [ ] Connected to Sonarr:
  - Sonarr Server: `http://sonarr:8989`
  - API Key: Your Sonarr API key

### 6. Bazarr (http://localhost:6767)
- [ ] Completed setup wizard
- [ ] Added languages for subtitles
- [ ] Connected to Radarr:
  - Address: `http://radarr`
  - Port: `7878`
  - API Key: Your Radarr API key
- [ ] Connected to Sonarr:
  - Address: `http://sonarr`
  - Port: `8989`
  - API Key: Your Sonarr API key

### 7. Tautulli (http://localhost:8181)
- [ ] Completed setup wizard
- [ ] Connected to Plex server
- [ ] Got API Key: `_______________`

### 8. Overseerr (http://localhost:5055) - Optional
- [ ] Completed setup wizard
- [ ] Connected to Plex
- [ ] Connected to Radarr (API key)
- [ ] Connected to Sonarr (API key)

---

## 🔄 Update Configuration Files (Second Pass)

Now that you have all API keys, update:

### `docker-compose.yml`
- [ ] Updated RADARR_API_KEY
- [ ] Updated SONARR_API_KEY

### `tautulliScripts/trakt_scrobbler.py`
- [ ] Updated TAUTULLI_API_KEY

### `config/fetcharr/fetcharr.yaml`
- [ ] Updated Sonarr api_key
- [ ] Updated Radarr api_key

### Restart Services
```bash
docker compose down
docker compose up -d
```
- [ ] Services restarted

---

## 🔐 Trakt Authentication

### Authenticate Trakt Watchlist Sync
```bash
docker compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup
```
- [ ] Visited verification URL
- [ ] Entered code
- [ ] Authorized application
- [ ] Confirmed success

### Authenticate Trakt Scrobbler
```bash
docker exec -it tautulli bash
cd /scripts
python3 trakt_scrobbler.py --setup
# Follow prompts
python3 trakt_scrobbler.py --test
exit
```
- [ ] Setup completed
- [ ] Test successful

---

## 📝 Tautulli Script Configuration

Tautulli → Settings → Notification Agents → Add Script

**Configuration:**
- [ ] Script Folder: `/scripts`
- [ ] Script File: `./trakt_scrobbler.py`

**Triggers:**
- [ ] Playback Start ✓
- [ ] Playback Stop ✓
- [ ] Playback Pause ✓
- [ ] Playback Resume ✓

**Conditions:**
- [ ] Media Type is: movie, episode

**Arguments:**
- [ ] Playback Start: (see SETUP.md for full arguments)
- [ ] Playback Stop: (see SETUP.md for full arguments)
- [ ] Playback Pause: (see SETUP.md for full arguments)
- [ ] Playback Resume: (see SETUP.md for full arguments)

- [ ] Saved configuration
- [ ] Tested script

---

## 🪝 Webhook Setup

### Radarr Webhook
Radarr → Settings → Connect → Add → Webhook
- [ ] Name: `Trakt Cleanup`
- [ ] On Delete: ✓
- [ ] URL: `http://trakt-watchlist-cleanup:5000/radarr`
- [ ] Method: POST
- [ ] Saved

### Sonarr Webhook
Sonarr → Settings → Connect → Add → Webhook
- [ ] Name: `Trakt Cleanup`
- [ ] On Series Delete: ✓
- [ ] URL: `http://trakt-watchlist-cleanup:5000/sonarr`
- [ ] Method: POST
- [ ] Saved

---

## ✅ Final Testing

### Test Trakt Watchlist Sync
- [ ] Add a movie to Trakt watchlist
- [ ] Wait 20 seconds
- [ ] Check Radarr → Movies (should appear)
- [ ] Check logs: `docker compose logs trakt-watchlist-sync`

### Test Trakt Scrobbler
- [ ] Play something in Plex
- [ ] Check Trakt.tv → Progress (should update)
- [ ] Check Tautulli logs for script execution

### Test Fetcharr
- [ ] Add something to Plex watchlist
- [ ] Check Radarr/Sonarr (should appear)
- [ ] Check logs: `docker compose logs fetcharr`

### Test Downloads
- [ ] Manually search in Radarr or Sonarr
- [ ] Verify download starts in Deluge
- [ ] Verify file moves to correct directory
- [ ] Verify media appears in Plex

---

## 🎉 Setup Complete!

### Quick Reference - Service URLs

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| Plex | http://localhost:32400/web | Plex account |
| Radarr | http://localhost:7878 | No auth by default |
| Sonarr | http://localhost:8989 | No auth by default |
| Prowlarr | http://localhost:9696 | No auth by default |
| Deluge | http://localhost:8112 | deluge / [your changed password] |
| Bazarr | http://localhost:6767 | No auth by default |
| Tautulli | http://localhost:8181 | Set during setup |
| Overseerr | http://localhost:5055 | Set during setup |
| Fetcharr | http://localhost:8080 | No web UI |

### Quick Commands
```bash
# Start services
./manage.sh start

# Stop services
./manage.sh stop

# View logs
./manage.sh logs [service-name]

# Check status
./manage.sh status
```

---

## 📊 API Keys Reference

Keep this for reference:

| Service | API Key |
|---------|---------|
| Radarr | `_______________` |
| Sonarr | `_______________` |
| Tautulli | `_______________` |
| Plex Token | `_______________` |
| Trakt Client ID | `_______________` |
| Trakt Client Secret | `_______________` |

---

## 🐛 Common Issues

### Services won't start
- [ ] Check logs: `docker compose logs <service>`
- [ ] Check ports aren't in use: `sudo netstat -tulpn | grep <port>`

### Plex claim token expired
- [ ] Get new token: https://www.plex.tv/claim/
- [ ] Update docker-compose.yml
- [ ] Restart: `docker compose restart plex`

### Trakt not working
- [ ] Re-authenticate: `docker compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup`
- [ ] Check credentials in docker-compose.yml

### Downloads not starting
- [ ] Check Prowlarr indexers working
- [ ] Check Deluge connected in Radarr/Sonarr
- [ ] Check Radarr/Sonarr logs

---

**Setup Time Estimate:** 30-45 minutes

**Support:** See SETUP.md for detailed troubleshooting
