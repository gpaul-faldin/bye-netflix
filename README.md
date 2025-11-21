# ReplaceNetflix - Automated Media Server Stack

A complete, automated media server setup using Docker with Plex, Radarr, Sonarr, and Trakt integration.

## 🎯 What This Does

This project creates a fully automated media server that:

- **Streams** your media via Plex (like Netflix)
- **Automatically downloads** movies/shows from your Trakt or Plex watchlist
- **Manages downloads** via Deluge torrent client
- **Tracks your viewing** on Trakt.tv
- **Downloads subtitles** automatically via Bazarr
- **Monitors everything** with beautiful stats via Tautulli

## 🚀 Quick Start

```bash
# 1. Clone the repository
git clone <repository-url>
cd ReplaceNetflix

# 2. Follow the setup guide
# See CHECKLIST.md for a quick setup checklist
# See SETUP.md for detailed instructions

# 3. Start services
docker compose up -d
```

## 📚 Documentation

- **[CHECKLIST.md](./CHECKLIST.md)** - Quick setup checklist with all required values to fill in
- **[SETUP.md](./SETUP.md)** - Complete detailed setup guide with explanations

## 🛠️ Stack Components

### Core Services
- **Plex** (Port 32400) - Media server
- **Radarr** (Port 7878) - Movie management
- **Sonarr** (Port 8989) - TV show management
- **Deluge** (Port 8112) - Torrent client
- **Prowlarr** (Port 9696) - Indexer manager

### Enhancement Services
- **Bazarr** (Port 6767) - Subtitle management
- **Tautulli** (Port 8181) - Plex monitoring & statistics
- **Overseerr** (Port 5055) - Request management (optional)
- **Fetcharr** (Port 8080) - Plex watchlist integration

### Automation Services
- **Trakt Watchlist Sync** - Auto-download from Trakt watchlist
- **Trakt Watchlist Cleanup** - Remove from Trakt when deleted
- **Trakt Scrobbler** - Track viewing progress on Trakt
- **YggTorrent Indexer** - French content indexer (optional)

## 🎬 Workflow

1. **Add content to your watchlist:**
   - Add movies/shows to Trakt.tv or Plex watchlist
   
2. **Automatic download:**
   - Content is automatically added to Radarr/Sonarr
   - Searches for best quality via Prowlarr
   - Downloads via Deluge
   - Subtitles added via Bazarr
   
3. **Watch in Plex:**
   - Content appears automatically in Plex
   - Your viewing progress syncs to Trakt.tv
   - Statistics tracked in Tautulli

4. **Automatic cleanup:**
   - Delete from Radarr/Sonarr removes from Trakt watchlist

## 📋 Prerequisites

Before starting, you need:

1. **Accounts:**
   - Trakt.tv account (free)
   - Plex account
   - YggTorrent account (optional, for French content)

2. **System:**
   - Docker & Docker Compose installed
   - At least 20GB free space (more for media)
   - Linux/Windows/macOS with Docker support

3. **Network:**
   - Internet connection
   - Ports 32400, 7878, 8989, etc. available

## ⚙️ Configuration Required

**Before starting services, you need to configure:**

1. ✅ Trakt API credentials (Client ID & Secret)
2. ✅ Plex claim token & API token
3. ✅ YggTorrent credentials (if using)
4. ✅ Timezone setting

**After starting services, you'll configure:**

5. ✅ Radarr API key
6. ✅ Sonarr API key  
7. ✅ Tautulli API key

See [CHECKLIST.md](./CHECKLIST.md) for all values to fill in.

## 🎯 Setup Time

- **First-time setup:** 30-45 minutes
- **Configuration:** 15-20 minutes
- **Testing:** 5-10 minutes

**Total:** About 1 hour

## 📖 How to Use This Project

### For First-Time Setup

1. **Start with [CHECKLIST.md](./CHECKLIST.md)**
   - Print it or keep it open in a browser
   - Fill in all required values as you go
   - Check off completed steps

2. **Reference [SETUP.md](./SETUP.md) when needed**
   - Detailed explanations for each step
   - Troubleshooting section
   - Advanced configuration options

### For Maintenance

```bash
# Start services
./manage.sh start

# Stop services
./manage.sh stop

# Restart services
./manage.sh restart

# Update all services
./manage.sh update

# View logs
./manage.sh logs [service-name]

# Check status
./manage.sh status
```

## 🗂️ Directory Structure

```
ReplaceNetflix/
├── config/                     # Service configurations
│   ├── plex/                   # Plex config & metadata
│   ├── radarr/                 # Radarr database & config
│   ├── sonarr/                 # Sonarr database & config
│   ├── prowlarr/               # Prowlarr indexers config
│   ├── deluge/                 # Deluge settings
│   ├── bazarr/                 # Bazarr subtitles config
│   ├── tautulli/               # Tautulli stats & config
│   ├── overseerr/              # Overseerr settings
│   ├── fetcharr/               # Fetcharr config
│   ├── ygege/                  # YggTorrent indexer config
│   └── trakt-watchlist-sync/   # Trakt tokens
├── srv/                        # Media storage
│   ├── downloads/              # Download staging
│   │   ├── complete/           # Completed downloads
│   │   └── incomplete/         # In-progress downloads
│   ├── movies/                 # Movie library
│   └── tv/                     # TV show library
├── tautulliScripts/            # Tautulli automation scripts
│   └── trakt_scrobbler.py      # Trakt scrobbling script
├── trakt-watchlist-sync/       # Trakt watchlist services
│   ├── trakt-watchlist-sync.py
│   └── trakt-watchlist-cleanup.py
├── docker-compose.yml          # Service definitions
├── .env                        # Environment variables
├── manage.sh                   # Management script
├── SETUP.md                    # Detailed setup guide
├── CHECKLIST.md                # Quick setup checklist
└── README.md                   # This file
```

## 🔒 Security Notes

- Keep API keys private
- Change default passwords (Deluge, etc.)
- Don't commit credentials to version control
- Consider using a VPN for torrenting
- Use a reverse proxy for external access

## 🐛 Troubleshooting

Common issues and solutions:

### Services won't start
```bash
docker compose logs <service-name>
```

### Plex claim token expired
Get new token: https://www.plex.tv/claim/

### Trakt authentication failed
```bash
docker compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup
```

### Downloads not starting
1. Check Prowlarr indexers
2. Check Radarr/Sonarr download clients
3. Check Deluge is running

For detailed troubleshooting, see [SETUP.md](./SETUP.md#troubleshooting).

## 📊 Service Access

Once running, access services at:

| Service | URL | Purpose |
|---------|-----|---------|
| Plex | http://localhost:32400/web | Watch your media |
| Radarr | http://localhost:7878 | Manage movies |
| Sonarr | http://localhost:8989 | Manage TV shows |
| Prowlarr | http://localhost:9696 | Manage indexers |
| Deluge | http://localhost:8112 | Manage downloads |
| Bazarr | http://localhost:6767 | Manage subtitles |
| Tautulli | http://localhost:8181 | View statistics |
| Overseerr | http://localhost:5055 | Request content |

## 🎉 What's Automated

After setup, everything runs automatically:

✅ New items in watchlist → Downloaded automatically  
✅ Downloads complete → Organized in Plex  
✅ Watching in Plex → Progress tracked on Trakt  
✅ Finished watching → Marked watched on Trakt  
✅ Delete from library → Removed from watchlist  
✅ Missing subtitles → Downloaded automatically  

## 🤝 Contributing

Feel free to:
- Report issues
- Suggest improvements
- Share your configurations
- Contribute code

## 📝 License

This project configuration is provided as-is for personal use.

## 🙏 Credits

Built with these amazing projects:
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

---

**Ready to get started?** Head to [CHECKLIST.md](./CHECKLIST.md) to begin! 🚀
