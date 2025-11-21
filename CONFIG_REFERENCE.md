# Configuration Reference Guide

Quick reference for all configuration values needed in the ReplaceNetflix project.

## 📋 Configuration Files Overview

This document lists every configuration file and what values need to be changed.

---

## 1. `.env` File

**Location:** `./env`

**Purpose:** Configure media directory location

```env
# Where all media will be stored
MEDIA_DIR=/srv
```

**Required Changes:**
- Only change if you want media stored elsewhere
- Default `/srv` works for most setups

---

## 2. `docker-compose.yml`

**Location:** `./docker-compose.yml`

### Plex Service

**Lines to modify:**
```yaml
environment:
  - PUID=1000                                  # Your user ID (run: id -u)
  - PGID=1000                                  # Your group ID (run: id -g)
  - TZ=Europe/Paris                            # Your timezone
  - PLEX_CLAIM=claim-XXXXXXXXXXXXXXXXXXXX      # From https://www.plex.tv/claim/
```

**How to get values:**
- **PUID:** Run `id -u` in terminal
- **PGID:** Run `id -g` in terminal  
- **TZ:** See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
- **PLEX_CLAIM:** Visit https://www.plex.tv/claim/ (valid 4 minutes)

---

### Trakt Watchlist Sync Service

**Lines to modify:**
```yaml
environment:
  - TRAKT_CLIENT_ID=6a329068fe5503480ceaeb5477493a75f7230a457834a0e3f3c0704e7ad0a7fc
  - TRAKT_CLIENT_SECRET=b278d963bf8e729b6c9d0cb52b1c651c1fb8d08ccd54bd6c0fc92da8df81f263
  - RADARR_API_KEY=bcdb83d1f0be438eae81fa3274b29e7e       # From Radarr after setup
  - SONARR_API_KEY=7d577808c2c94fabb298ca5ed82fbadc       # From Sonarr after setup
  - RADARR_ROOT_FOLDER=/srv/movies/
  - SONARR_ROOT_FOLDER=/srv/tv/
  - RADARR_QUALITY_PROFILE=Any
  - SONARR_QUALITY_PROFILE=Any
  - POLL_INTERVAL=20                                      # Seconds between checks
```

**How to get values:**
- **TRAKT_CLIENT_ID/SECRET:** https://trakt.tv/oauth/applications/new
- **RADARR_API_KEY:** Radarr → Settings → General → Security → API Key
- **SONARR_API_KEY:** Sonarr → Settings → General → Security → API Key
- **ROOT_FOLDERS:** Change if MEDIA_DIR changed in .env
- **QUALITY_PROFILE:** Must match profile names in Radarr/Sonarr
- **POLL_INTERVAL:** Increase to reduce API calls (e.g., 60, 300, 600)

---

### Trakt Watchlist Cleanup Service

**Lines to modify:**
```yaml
environment:
  - TRAKT_CLIENT_ID=6a329068fe5503480ceaeb5477493a75f7230a457834a0e3f3c0704e7ad0a7fc
  - TRAKT_CLIENT_SECRET=b278d963bf8e729b6c9d0cb52b1c651c1fb8d08ccd54bd6c0fc92da8df81f263
```

**How to get values:**
- Same as Trakt Watchlist Sync above

---

## 3. `config/ygege/config.json`

**Location:** `./config/ygege/config.json`

**Purpose:** YggTorrent indexer credentials (French content)

```json
{
    "username": "MyYggUsername",
    "password": "MySecretPassword",
    "bind_ip": "0.0.0.0",
    "bind_port": 8715,
    "log_level": "debug"
}
```

**Required Changes:**
- Replace `username` with your YggTorrent username
- Replace `password` with your YggTorrent password
- Leave other values as-is

**Note:** If you don't use YggTorrent:
- Comment out the `ygege` service in docker-compose.yml
- Skip this configuration

---

## 4. `config/fetcharr/fetcharr.yaml`

**Location:** `./config/fetcharr/fetcharr.yaml`

**Purpose:** Plex watchlist integration

```yaml
plex:
  api_token: YOUR_PLEX_TOKEN_HERE               # From Plex
  sync_friends_watchlist: false

sonarr:
  default:
    enabled: true
    base_url: http://sonarr:8989
    api_key: f30530c92c5c4bc49810213e82aeff20    # From Sonarr
    root_folder: /tv
    quality_profile: HD-1080p                    # Optional
    monitored: true
    search_immediately: true

radarr:
  default:
    enabled: true
    base_url: http://radarr:7878
    api_key: b8c75abea9264513a247bdd240bf3d3b    # From Radarr
    root_folder: /movies
    quality_profile: HD-1080p                    # Optional
    monitored: true
    search_immediately: true
```

**Required Changes:**
- **plex.api_token:** https://support.plex.tv/articles/204059436/
- **sonarr.api_key:** Sonarr → Settings → General → API Key
- **radarr.api_key:** Radarr → Settings → General → API Key
- **quality_profile:** Optional, comment out to use default

**Optional Changes:**
- **sync_friends_watchlist:** Set to `true` to include friends' watchlists
- **root_folder:** Change if media paths are different
- **monitored:** Set to `false` to not auto-monitor new content
- **search_immediately:** Set to `false` to not auto-search

---

## 5. `tautulliScripts/trakt_scrobbler.py`

**Location:** `./tautulliScripts/trakt_scrobbler.py`

**Purpose:** Sync Plex viewing to Trakt.tv

**Lines to modify (around line 54-61):**
```python
# ## CONFIGURATION - EDIT THESE SETTINGS ##
TRAKT_CLIENT_ID = '6a329068fe5503480ceaeb5477493a75f7230a457834a0e3f3c0704e7ad0a7fc'
TRAKT_CLIENT_SECRET = 'b278d963bf8e729b6c9d0cb52b1c651c1fb8d08ccd54bd6c0fc92da8df81f263'
TRAKT_REDIRECT_URI = 'urn:ietf:wg:oauth:2.0:oob'

# Tautulli API configuration
TAUTULLI_URL = 'http://tautulli:8181'
TAUTULLI_API_KEY = '5c7bdfb1ff274ef59f74df5d2bc6009c'    # From Tautulli
```

**Required Changes:**
- **TRAKT_CLIENT_ID:** From https://trakt.tv/oauth/applications/new
- **TRAKT_CLIENT_SECRET:** From https://trakt.tv/oauth/applications/new
- **TAUTULLI_API_KEY:** Tautulli → Settings → Web Interface → API Key

**Optional Changes (around line 64-67):**
```python
# Minimum watch percentage to mark as "watched" (80% = 0.8)
WATCH_THRESHOLD = 0.8

# Enable debug logging
VERBOSE_LOGGING = True
```

---

## 📝 Setup Order

### Phase 1: Before Starting Containers

1. ✅ `.env` (optional)
2. ✅ `docker-compose.yml` - Plex section (PLEX_CLAIM required!)
3. ✅ `docker-compose.yml` - Trakt sections (CLIENT_ID/SECRET)
4. ✅ `config/ygege/config.json` (if using YggTorrent)
5. ✅ `tautulliScripts/trakt_scrobbler.py` - Trakt credentials + TOKEN_FILE

### Phase 2: Start Containers
```bash
docker compose up -d
```

### Phase 3: After Initial Service Setup

6. ✅ Get API keys from services (Radarr, Sonarr, Tautulli)
7. ✅ Update `docker-compose.yml` with API keys
8. ✅ Update `config/fetcharr/fetcharr.yaml` with tokens and API keys  
9. ✅ Update `tautulliScripts/trakt_scrobbler.py` with Tautulli API key

### Phase 4: Restart & Authenticate
```bash
docker compose down
docker compose up -d

# Authenticate Trakt services
docker compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup

docker exec -it tautulli bash
cd /scripts
python3 trakt_scrobbler.py --setup
python3 trakt_scrobbler.py --test
exit
```

---

## 🔑 Quick Reference - Where to Get API Keys

| Key | Where to Get It |
|-----|----------------|
| **Plex Claim Token** | https://www.plex.tv/claim/ (expires in 4 min) |
| **Plex API Token** | https://support.plex.tv/articles/204059436/ |
| **Trakt Client ID** | https://trakt.tv/oauth/applications/new |
| **Trakt Client Secret** | https://trakt.tv/oauth/applications/new |
| **Radarr API Key** | Radarr → Settings → General → Security → API Key |
| **Sonarr API Key** | Sonarr → Settings → General → Security → API Key |
| **Tautulli API Key** | Tautulli → Settings → Web Interface → API Key |

---

## 🎯 Configuration Validation Checklist

Before starting services:
- [ ] Plex claim token obtained (valid 4 minutes)
- [ ] Trakt app created with Client ID/Secret
- [ ] YggTorrent credentials ready (if using)
- [ ] Timezone set correctly
- [ ] TOKEN_FILE path is absolute in trakt_scrobbler.py

After service setup:
- [ ] Radarr API key obtained and updated
- [ ] Sonarr API key obtained and updated
- [ ] Tautulli API key obtained and updated
- [ ] Plex API token obtained and updated
- [ ] All services restarted with new configuration
- [ ] Trakt authentication completed

---

## 🔍 Finding Your User/Group ID

```bash
# Find your user ID
id -u
# Output: 1000

# Find your group ID  
id -g
# Output: 1000

# Find your username
whoami
# Output: your_username
```

Use these values for PUID and PGID in docker-compose.yml.

---

## 🌍 Common Timezones

| Location | Timezone String |
|----------|----------------|
| New York, USA | `America/New_York` |
| Los Angeles, USA | `America/Los_Angeles` |
| Chicago, USA | `America/Chicago` |
| London, UK | `Europe/London` |
| Paris, France | `Europe/Paris` |
| Berlin, Germany | `Europe/Berlin` |
| Tokyo, Japan | `Asia/Tokyo` |
| Sydney, Australia | `Australia/Sydney` |
| Toronto, Canada | `America/Toronto` |

Full list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

---

## ⚙️ Default Ports Reference

| Service | Port | Protocol |
|---------|------|----------|
| Plex | 32400 | HTTP |
| Radarr | 7878 | HTTP |
| Sonarr | 8989 | HTTP |
| Prowlarr | 9696 | HTTP |
| Deluge Web | 8112 | HTTP |
| Deluge Daemon | 58846 | Daemon |
| Deluge Torrent | 6881 | TCP/UDP |
| Bazarr | 6767 | HTTP |
| Tautulli | 8181 | HTTP |
| Overseerr | 5055 | HTTP |
| Fetcharr | 8080 | HTTP |
| YGGege | 8715 | HTTP |
| Trakt Cleanup | 5000 | HTTP |
| Flaresolverr | 8191 | HTTP |

---

## 📂 File Paths Reference

**Configuration Files:**
```
./config/plex/              # Plex configuration
./config/radarr/            # Radarr database
./config/sonarr/            # Sonarr database
./config/prowlarr/          # Prowlarr indexers
./config/deluge/            # Deluge settings
./config/bazarr/            # Bazarr settings
./config/tautulli/          # Tautulli database
./config/fetcharr/          # Fetcharr config
./config/ygege/             # YggTorrent credentials
./config/trakt-watchlist-sync/  # Trakt tokens
```

**Media Files (inside containers):**
```
/srv/movies/              # Movie library
/srv/tv/                  # TV show library
/srv/downloads/complete/  # Completed downloads
/srv/downloads/incomplete/ # In-progress downloads
```

**Scripts:**
```
/scripts/trakt_scrobbler.py  # Inside Tautulli container
/app/trakt-watchlist-sync.py # Inside sync container
/app/trakt-watchlist-cleanup.py # Inside cleanup container
```

---

## 🆘 Support

For detailed setup instructions: See [SETUP.md](./SETUP.md)  
For quick setup checklist: See [CHECKLIST.md](./CHECKLIST.md)  
For troubleshooting: See [SETUP.md#troubleshooting](./SETUP.md#troubleshooting)
