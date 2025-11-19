# Automated Media Server Stack

A complete Docker-based media automation stack with Plex, Radarr, Sonarr, Prowlarr, and YggTorrent integration.

## 🎯 What This Does

- **Request content** from smart TV/phone → **Automatically downloads** → **Appears in Plex**
- **4K quality optimization** - avoids massive REMUX files
- **French torrent support** via YggTorrent
- **Subtitle automation** with Bazarr
- **Plex watchlist integration** for Android TV requests

## 📋 Requirements

- **Linux server** with Docker and Docker Compose
- **YggTorrent account** with credentials
- **Plex account** (free tier works)
- **20GB+ free space** minimum
- **Same filesystem** for downloads and media (for hardlinks)

## 🚀 Quick Start

1. **Clone and setup:**
```bash
git clone <your-repo>
cd media-server
chmod +x setup.sh
./setup.sh
```

2. **Follow the interactive prompts** for credentials
3. **Access web interfaces** and complete final configuration
4. **Start requesting content!**

## 📁 Directory Structure

```
media-server/
├── docker-compose.yml         # Main configuration
├── setup.sh                  # Automated setup script
├── config/                   # Persistent container configs
│   ├── plex/
│   ├── radarr/
│   ├── sonarr/
│   ├── prowlarr/
│   ├── overseerr/
│   ├── bazarr/
│   ├── fetcharr/
│   └── ygege/
├── downloads/                # Torrent staging area
│   ├── incomplete/
│   └── complete/
└── media/                   # Final organized library
    ├── movies/
    └── tv/
```

## 🔧 Manual Configuration Steps

If you prefer manual setup or the script fails:

### 1. Initial Setup
```bash
# Create directories (example using MEDIA_DIR=/srv)
mkdir -p {config/{plex,radarr,sonarr,prowlarr,overseerr,bazarr,fetcharr,ygege},/srv/downloads/{incomplete,complete},/srv/{movies,tv}}

# Start containers (use whichever compose command your system provides)
# If you have Docker Compose v2 (recommended):
docker compose up -d
# Otherwise, with the older docker-compose binary:
docker-compose up -d
```

### 2. Plex Setup
1. Get claim token: https://plex.tv/claim
2. Update `PLEX_CLAIM` in docker-compose.yml
3. Access: `http://server:32400/web`
4. Add libraries:
   - Movies: `/data/media/movies`
   - TV Shows: `/data/media/tv`

### 3. YggTorrent Configuration
1. Create `./config/ygege/config.json`:
```json
{
  "username": "your_ygg_username",
  "password": "your_ygg_password"
}
```

### 4. Prowlarr Setup
1. Access: `http://server:9696`
2. Add indexers:
   - **Ygege**: `http://ygege:8715`
   - **YggAPI**: Configure with your credentials
3. Settings → Apps → Add Radarr/Sonarr connections

### 5. Radarr Configuration
1. Access: `http://server:7878`
2. Settings → Media Management:
   - **Root Folders**: `/movies`
   - **Use Hardlinks**: ✅ Enable
3. Settings → Download Clients:
   - **Deluge**: `http://deluge:8112`, password: `deluge`
4. Quality Profiles:
   - Edit "Any" or create custom 4K profile
   - Prefer: Upgrade until WEB-2160p
   - Remove: REMUX and lower qualities (minimum HDTV-1080p)

### 6. Sonarr Configuration
1. Access: `http://server:8989`
2. Settings → Media Management:
   - **Root Folders**: `/tv`
   - **Use Hardlinks**: ✅ Enable
3. Settings → Download Clients:
   - **Deluge**: `http://deluge:8112`, password: `deluge`
4. Quality Profile: Configure similar to Radarr

### 7. Deluge Configuration
1. Access: `http://server:8112`, password: `deluge`
2. Preferences → Downloads:
   - **Download to** (inside container): `/downloads/incomplete`
   - **Move completed to** (inside container): `/downloads/complete`
     (these are mapped to `${MEDIA_DIR:-/srv}/downloads/incomplete` and `.../complete` on the host)
   - **✅ Move completed downloads**

### 8. Overseerr Setup
1. Access: `http://server:5055`
2. Connect to Plex: `http://plex:32400`
3. Add servers:
   - **Radarr**: `http://radarr:7878`, Quality: "Any", Root: `/movies`
   - **Sonarr**: `http://sonarr:8989`, Quality: "Any", Root: `/tv`

### 9. Bazarr (Subtitles)
1. Access: `http://server:6767`
2. Settings → Sonarr/Radarr: Connect to your instances
3. Settings → Providers: Add subtitle providers
4. Settings → Languages: Configure preferences

### 10. Fetcharr (Plex Watchlist)
1. Access: `http://server:8080`
2. Configure Plex and Trakt connections
3. Enable watchlist monitoring

## 🎛️ Web Interface Access

| Service | URL | Purpose |
|---------|-----|---------|
| Plex | `http://server:32400/web` | Media streaming |
| Overseerr | `http://server:5055` | Request interface |
| Radarr | `http://server:7878` | Movie management |
| Sonarr | `http://server:8989` | TV show management |
| Prowlarr | `http://server:9696` | Indexer management |
| Deluge | `http://server:8112` | Torrent client |
| Bazarr | `http://server:6767` | Subtitle management |
| Fetcharr | `http://server:8080` | Watchlist integration |

## 🔧 Quality Profile Recommendations

### Movies (Radarr)
**Priority order:**
1. WEB-DL 2160p (15-30GB)
2. WEBRip 2160p (10-20GB)  
3. Bluray 2160p (8-15GB)
4. WEB-DL 1080p (fallback)

**Avoid:** REMUX (80-150GB files)

### TV Shows (Sonarr)
**Similar priorities, per episode:**
1. WEB-DL 2160p (3-8GB)
2. WEBRip 2160p (2-5GB)
3. Bluray 2160p (2-4GB)

## 🎯 Usage Workflow

### Smart TV Requests
1. **Browse** content in Overseerr web interface
2. **Click request** for movies/shows you want
3. **Automatic download** begins via Radarr/Sonarr
4. **Content appears** in Plex when ready

### Android TV (Alternative)
1. **Add to Plex Watchlist** in Plex app
2. **Fetcharr monitors** watchlist
3. **Auto-requests** via Radarr/Sonarr
4. **Downloads automatically**

### Manual Downloads
For older content or complete series:
1. **Search in Prowlarr**
2. **Download directly** to Deluge
3. **Let Radarr/Sonarr import** and organize

## 🔒 VPN Setup (Optional)

Uncomment the gluetun section in docker-compose.yml:

```yaml
gluetun:
  image: qmcgaw/gluetun:latest
  environment:
    - VPN_SERVICE_PROVIDER=your_provider
    - OPENVPN_USER=your_user
    - OPENVPN_PASSWORD=your_pass
```

Then modify deluge service:
```yaml
deluge:
  network_mode: "service:gluetun"
  depends_on: [gluetun]
  # Remove ports section
```

## 🐛 Troubleshooting

### Downloads stuck at 0%
- Check if containers can communicate: `docker exec -it radarr ping deluge`
- Verify paths are consistent between containers
- Check deluge daemon connection

### Hardlinks not working
- Ensure downloads and media folders are on same filesystem
 - Check `df ${MEDIA_DIR:-./media}/downloads` vs `df ${MEDIA_DIR:-./media}` should match (host paths should be on the same filesystem; default MEDIA_DIR=/srv)
- Enable hardlinks in Radarr/Sonarr settings

### No 4K content found
- Search with specific terms: "movie name 2160p"
- Check Prowlarr indexer categories include UHD/4K
- Verify YggTorrent indexers are working

### Overseerr requests not downloading
- Check Radarr/Sonarr connections in Overseerr
- Verify API keys are correct
- Test indexers in Prowlarr

## 📈 Performance Tips

- **Use hardlinks** to avoid duplicate storage
- **Set reasonable quality profiles** to avoid massive files
- **Monitor disk space** - 4K content uses significant storage
- **Regular maintenance** - clean up old downloads periodically

## 🔄 Updates

```bash
# Update containers (use either docker compose or docker-compose)
docker compose pull || docker-compose pull
docker compose up -d || docker-compose up -d

# Backup configs before major updates
tar -czf backup-$(date +%Y%m%d).tar.gz ./config/
```

## 🆘 Support

 - Check container logs: `docker compose logs <service_name>` or `docker-compose logs <service_name>`
 - Restart specific service: `docker compose restart <service_name>` or `docker-compose restart <service_name>`
 - Full restart: `docker compose down && docker compose up -d` or `docker-compose down && docker-compose up -d`

---

**Result:** Complete "request → download → watch" automation with 4K support and French content integration.
