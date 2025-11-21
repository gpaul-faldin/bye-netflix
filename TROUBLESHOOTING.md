# Troubleshooting Guide

Common issues and their solutions for the ReplaceNetflix media stack.

## Table of Contents
- [General Issues](#general-issues)
- [Plex Issues](#plex-issues)
- [Radarr/Sonarr Issues](#radarrsonarr-issues)
- [Prowlarr Issues](#prowlarr-issues)
- [Deluge Issues](#deluge-issues)
- [Trakt Issues](#trakt-issues)
- [Network Issues](#network-issues)
- [Permission Issues](#permission-issues)
- [Performance Issues](#performance-issues)

---

## General Issues

### Services Won't Start

**Symptoms:**
- Container exits immediately
- `docker compose ps` shows service as "Exited"

**Solutions:**

1. **Check logs:**
```bash
docker compose logs <service-name>
```

2. **Check port conflicts:**
```bash
# Linux/Mac
sudo netstat -tulpn | grep <port>

# Windows  
netstat -ano | findstr <port>
```

3. **Common fixes:**
```bash
# Restart Docker
sudo systemctl restart docker

# Remove and recreate containers
docker compose down
docker compose up -d

# Check for typos in docker-compose.yml
docker compose config
```

---

### Can't Access Web Interface

**Symptoms:**
- Browser shows "Connection refused"
- "This site can't be reached"

**Solutions:**

1. **Verify service is running:**
```bash
docker compose ps
# Should show "Up" status
```

2. **Check if port is listening:**
```bash
docker compose ps
# Look for PORT column: 0.0.0.0:7878->7878/tcp
```

3. **Try different URLs:**
```bash
# Try all of these:
http://localhost:7878
http://127.0.0.1:7878
http://YOUR_SERVER_IP:7878
```

4. **Check firewall:**
```bash
# Linux - temporarily disable
sudo ufw disable

# Check if accessible now
# If yes, add firewall rule:
sudo ufw allow 7878/tcp
sudo ufw enable
```

---

### Configuration Changes Not Applied

**Symptoms:**
- Made changes to files but nothing changed
- Old values still showing

**Solutions:**

1. **Restart specific service:**
```bash
docker compose restart <service-name>
```

2. **Recreate containers:**
```bash
docker compose down
docker compose up -d
```

3. **Force rebuild:**
```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

---

## Plex Issues

### Plex Setup Wizard Won't Load

**Symptoms:**
- Can't access initial setup at http://localhost:32400/web
- Shows "Unauthorized"

**Solutions:**

1. **Check claim token validity (expires in 4 minutes):**
```bash
# Get new token
# Visit: https://www.plex.tv/claim/

# Update docker-compose.yml
nano docker-compose.yml

# Restart Plex immediately
docker compose restart plex
```

2. **Access setup using SSH tunnel:**
```bash
# From your local machine
ssh -L 32400:localhost:32400 user@server-ip

# Then access: http://localhost:32400/web
```

---

### Plex Library Empty or Not Updating

**Symptoms:**
- No media showing in Plex
- New downloads not appearing

**Solutions:**

1. **Verify library paths:**
```bash
# Check if files exist
ls -la /srv/movies
ls -la /srv/tv

# Check from inside container
docker exec -it plex ls -la /srv/movies
```

2. **Force library scan:**
- Plex → Settings → Library → Scan Library Files

3. **Check permissions:**
```bash
ls -la /srv
# Should show: drwxr-xr-x ... 1000 1000

# Fix if needed:
sudo chown -R 1000:1000 /srv
```

4. **Check Plex logs:**
```bash
docker compose logs plex | grep -i error
```

---

### Plex Transcoding Issues

**Symptoms:**
- Video stuttering
- "Not powerful enough" error

**Solutions:**

1. **Enable hardware acceleration:**
- Plex → Settings → Transcoder → Hardware acceleration

2. **Reduce quality:**
- Plex player settings → Quality → Lower quality

3. **Pre-transcode files:**
```bash
# Install ffmpeg in host
sudo apt install ffmpeg

# Convert to compatible format
ffmpeg -i input.mkv -c:v h264 -c:a aac output.mp4
```

---

## Radarr/Sonarr Issues

### Not Finding Any Releases

**Symptoms:**
- Manual search shows no results
- "No results found" in interactive search

**Solutions:**

1. **Check Prowlarr connection:**
```bash
# Radarr/Sonarr → Settings → Indexers
# Test each indexer

# Check Prowlarr logs
docker compose logs prowlarr
```

2. **Verify indexers are enabled:**
```bash
# Prowlarr → Indexers
# Make sure indexers are enabled and working
# Test each one
```

3. **Check search criteria:**
- Lower quality requirements
- Check release date restrictions
- Verify language settings

4. **Manual test in Prowlarr:**
```bash
# Prowlarr → Search
# Try searching for same title
# Check if results appear
```

---

### Downloads Not Starting

**Symptoms:**
- Manual search works but "Grab" does nothing
- Status stuck on "Queued"

**Solutions:**

1. **Check Deluge connection:**
```bash
# Radarr/Sonarr → Settings → Download Clients
# Test connection to Deluge
```

2. **Verify Deluge is running:**
```bash
docker compose ps deluge
# Should show "Up"

# Check Deluge logs
docker compose logs deluge
```

3. **Check Deluge web interface:**
```bash
# Access http://localhost:8112
# Verify Deluge is working
```

4. **Check category settings:**
```bash
# Radarr/Sonarr → Settings → Download Clients → Deluge
# Category should be: radarr or sonarr
# Remote Path Mapping: check if needed
```

---

### Already Exists in Database

**Symptoms:**
- Can't add movie/show
- "This movie/show is already in your library"

**Solutions:**

1. **Find duplicate:**
```bash
# Radarr/Sonarr → Library
# Search for the title
# Check if duplicate exists
```

2. **Remove duplicate:**
```bash
# Click movie/show → Delete
# Choose "Delete Files" if needed
```

3. **Database corruption fix:**
```bash
# Stop service
docker compose stop radarr

# Backup database
cp ./config/radarr/radarr.db ./config/radarr/radarr.db.backup

# Restart
docker compose start radarr
```

---

## Prowlarr Issues

### Indexers Not Working

**Symptoms:**
- All indexers show "Failed"
- Test returns errors

**Solutions:**

1. **Check Flaresolverr:**
```bash
docker compose ps flaresolverr
# Should show "Up"

# Test Flaresolverr
curl http://localhost:8191/health
# Should return: {"status":"ok"}
```

2. **Check indexer configuration:**
```bash
# Prowlarr → Settings → Indexers
# Verify URLs are correct
# Test each indexer individually
```

3. **Check rate limiting:**
- Wait 10-15 minutes
- Indexers may rate-limit requests
- Check indexer logs for ban messages

---

### YggTorrent Not Working

**Symptoms:**
- ygege proxy not responding
- Can't connect to http://ygege:8715

**Solutions:**

1. **Check ygege container:**
```bash
docker compose ps ygege
docker compose logs ygege
```

2. **Verify credentials:**
```bash
cat ./config/ygege/config.json
# Check username and password
```

3. **Test YggTorrent website:**
- Try logging in at https://yggtorrent.fi
- Verify account is active
- Check if site is down

4. **Recreate ygege container:**
```bash
docker compose stop ygege
docker compose rm -f ygege
docker compose up -d ygege
```

---

## Deluge Issues

### Can't Connect to Daemon

**Symptoms:**
- Web UI shows "Connection failed"
- Can't access http://localhost:8112

**Solutions:**

1. **Check Deluge is running:**
```bash
docker compose ps deluge
docker compose logs deluge
```

2. **Reset Deluge password:**
```bash
# Access container
docker exec -it deluge bash

# Edit auth file
echo "deluge:newpassword:10" > /config/auth

# Restart
exit
docker compose restart deluge
```

3. **Check connection settings:**
```bash
# Default credentials:
# Username: deluge (lowercase!)
# Password: deluge (or what you changed it to)
# Port: 58846 (daemon), 8112 (web)
```

---

### Downloads Stuck at 0%

**Symptoms:**
- Torrents added but not downloading
- Status shows "Queued" or "Checking"

**Solutions:**

1. **Check connection status:**
```bash
# Deluge → Connection Manager
# Make sure "Connected" is checked
```

2. **Check port forwarding:**
```bash
# If using VPN, check port is forwarded
# Default: 6881
```

3. **Check disk space:**
```bash
df -h /srv
# Make sure space available
```

4. **Check torrent file integrity:**
```bash
# Remove torrent
# Re-add from Radarr/Sonarr
```

---

## Trakt Issues

### Authentication Failed

**Symptoms:**
- Setup script fails
- "Invalid credentials" error

**Solutions:**

1. **Verify Trakt credentials:**
```bash
# Check Client ID and Secret in:
# - docker-compose.yml
# - tautulliScripts/trakt_scrobbler.py

# Make sure they match your Trakt app
```

2. **Check Trakt app settings:**
```bash
# Visit: https://trakt.tv/oauth/applications
# Verify Redirect URI: urn:ietf:wg:oauth:2.0:oob
```

3. **Re-authenticate:**
```bash
# For watchlist sync:
docker compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup

# For scrobbler:
docker exec -it tautulli bash
cd /scripts
rm -f trakt_tokens.json  # Remove old tokens
python3 trakt_scrobbler.py --setup
exit
```

---

### Scrobbling Not Working

**Symptoms:**
- Playing in Plex but Trakt not updating
- No progress shown on Trakt.tv

**Solutions:**

1. **Check Tautulli script:**
```bash
# Tautulli → Settings → Notification Agents → Scripts
# Verify script is enabled for all playback events
```

2. **Test manually:**
```bash
docker exec -it tautulli bash
cd /scripts
python3 trakt_scrobbler.py --test
# Should show: "Successfully connected to Trakt"
exit
```

3. **Check Tautulli logs:**
```bash
docker compose logs tautulli | grep -i trakt
# Look for errors
```

4. **Verify TOKEN_FILE path:**
```bash
# In trakt_scrobbler.py
# Must be absolute path: /config/trakt_tokens.json
# NOT relative: ./trakt_tokens.json
```

5. **Check file exists and is writable:**
```bash
docker exec -it tautulli bash
ls -la /config/trakt_tokens.json
# Should exist and be readable
exit
```

---

### Watchlist Not Syncing

**Symptoms:**
- Added to Trakt but not appearing in Radarr/Sonarr
- Sync service not running

**Solutions:**

1. **Check sync service:**
```bash
docker compose ps trakt-watchlist-sync
docker compose logs trakt-watchlist-sync
```

2. **Verify API keys:**
```bash
# Check docker-compose.yml
# - RADARR_API_KEY
# - SONARR_API_KEY

# Test in Radarr/Sonarr:
# Settings → General → API Key
```

3. **Manual sync:**
```bash
docker compose restart trakt-watchlist-sync
docker compose logs -f trakt-watchlist-sync
# Watch for errors
```

4. **Check Trakt watchlist:**
```bash
# Visit: https://trakt.tv/users/your-username/watchlist
# Verify items are actually in watchlist
```

---

## Network Issues

### Containers Can't Communicate

**Symptoms:**
- Radarr can't connect to Prowlarr
- "Connection refused" errors between services

**Solutions:**

1. **Check network:**
```bash
docker network ls
# Should show: replacenetflix_media-network

docker network inspect replacenetflix_media-network
# Check all containers are connected
```

2. **Use service names, not localhost:**
```bash
# CORRECT:
http://prowlarr:9696
http://radarr:7878

# WRONG:
http://localhost:9696
http://127.0.0.1:7878
```

3. **Recreate network:**
```bash
docker compose down
docker network rm replacenetflix_media-network
docker compose up -d
```

---

### Can't Access from Other Devices

**Symptoms:**
- Works on server but not from other devices on network

**Solutions:**

1. **Find server IP:**
```bash
# Linux/Mac
ip addr show

# Windows
ipconfig
```

2. **Access using server IP:**
```bash
http://SERVER_IP:32400/web  # Plex
http://SERVER_IP:7878       # Radarr
# etc.
```

3. **Check firewall:**
```bash
# Ubuntu/Debian
sudo ufw status
sudo ufw allow from 192.168.1.0/24 to any port 32400
sudo ufw allow from 192.168.1.0/24 to any port 7878
# etc.

# CentOS/RHEL
sudo firewall-cmd --list-all
sudo firewall-cmd --permanent --add-port=32400/tcp
sudo firewall-cmd --reload
```

---

## Permission Issues

### Permission Denied Errors

**Symptoms:**
- "Permission denied" in logs
- Can't write files
- Can't read configuration

**Solutions:**

1. **Check ownership:**
```bash
ls -la /srv
ls -la ./config

# Should show:
# drwxr-xr-x ... 1000 1000
```

2. **Fix permissions:**
```bash
# Fix media directories
sudo chown -R 1000:1000 /srv

# Fix config directories
sudo chown -R 1000:1000 ./config

# Fix scripts
sudo chown -R 1000:1000 ./tautulliScripts
```

3. **Check PUID/PGID:**
```bash
# In docker-compose.yml
# Should match your user:
id -u  # PUID
id -g  # PGID
```

---

### Can't Delete Files

**Symptoms:**
- Radarr/Sonarr can't delete files
- "Access denied" when deleting

**Solutions:**

1. **Fix ownership:**
```bash
sudo chown -R 1000:1000 /srv/movies
sudo chown -R 1000:1000 /srv/tv
```

2. **Fix permissions:**
```bash
sudo chmod -R 755 /srv/movies
sudo chmod -R 755 /srv/tv
```

3. **Check from container:**
```bash
docker exec -it radarr bash
touch /srv/movies/test.txt
rm /srv/movies/test.txt
# If this works, permissions are OK
exit
```

---

## Performance Issues

### High CPU Usage

**Symptoms:**
- System slow
- `docker stats` shows high CPU

**Solutions:**

1. **Check which container:**
```bash
docker stats
# Look at CPU % column
```

2. **Common causes:**
- **Plex transcoding:** Disable or limit
- **Radarr/Sonarr scanning:** Wait for completion
- **Prowlarr searching:** Normal during searches

3. **Limit resources:**
```yaml
# In docker-compose.yml, add to problem service:
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 2G
```

---

### High Disk Usage

**Symptoms:**
- Disk full
- Downloads failing

**Solutions:**

1. **Check disk usage:**
```bash
df -h
du -sh /srv/*
```

2. **Clean up:**
```bash
# Docker cleanup
docker system prune -a

# Remove completed downloads
rm -rf /srv/downloads/complete/*

# Check Plex metadata cache
du -sh ./config/plex
```

3. **Enable automatic cleanup:**
```bash
# Radarr/Sonarr → Settings → Media Management
# Enable: Delete Empty Folders
# Enable: Delete Unmonitor