# Bye Netflix — Self-Hosted Media Stack

A fully automated, self-hosted media server. Add something to your Trakt watchlist → it downloads, streams via Plex, scrobbles back to Trakt, and fetches subtitles automatically.

---

## Quick Start

```bash
git clone <repo> bye-netflix && cd bye-netflix
./setup.sh
./start.sh
```

`setup.sh` asks what you need, generates `.env` and `start.sh`, and prints next steps.

---

## Architecture

```
  Trakt Watchlist ──→  trakt-sync  ──→  Radarr ──→  Deluge (VPN)
  Plex Watchlist  ──→  Fetcharr    ──→  Sonarr ──→  SABnzbd
                                          │
                                     Prowlarr (indexers, VPN)
                                          │
                                    Media Library
                                    /media
                                          │
                                        Plex
                                    Tautulli  Bazarr
                                          │
                        trakt-scrobbler ──┘  (play/pause/stop → Trakt)
                        trakt-cleanup  ←── Radarr/Sonarr delete webhooks
```

---

## Modular Compose Files

The stack is split into a base + optional modules. Mix and match what you need:

| File | What it adds | When to use |
|---|---|---|
| `docker-compose.yml` | Plex, Radarr, Sonarr, Prowlarr, Tautulli, Fetcharr | Always |
| `compose/torrent.yml` | Deluge torrent client | If you use torrents |
| `compose/usenet.yml` | SABnzbd usenet client | If you use usenet |
| `compose/vpn.yml` | Gluetun VPN + moves Deluge/Prowlarr behind it | If you want VPN for torrents |
| `compose/trakt.yml` | Trakt watchlist sync + cleanup | If you use Trakt |
| `compose/macvlan.yml` | Gives Plex a dedicated LAN IP | If you want LAN direct access |
| `compose/bazarr.yml` | Bazarr automatic subtitles | If you want auto-subtitles |

`setup.sh` generates a `start.sh` with the right combination for your setup.

**Example: torrents + VPN + Trakt**
```bash
docker compose -f docker-compose.yml -f compose/torrent.yml -f compose/vpn.yml -f compose/trakt.yml up -d
```

**Example: usenet only, no VPN**
```bash
docker compose -f docker-compose.yml -f compose/usenet.yml up -d
```

---

## Services

| Service | Purpose | Port |
|---|---|---|
| Plex | Media streaming | 32400 |
| Radarr | Movie automation | 7878 |
| Sonarr | TV automation | 8989 |
| Prowlarr | Indexer management | 9696 |
| Tautulli | Plex stats + script triggers | 8181 |
| Bazarr *(bazarr)* | Automatic subtitles | 6767 |
| Fetcharr | Plex watchlist → Radarr/Sonarr (background, no UI) | — |
| Deluge *(torrent)* | Torrent client | 8112 |
| SABnzbd *(usenet)* | Usenet client | 8085 |
| Gluetun *(vpn)* | VPN gateway | — |
| Trakt Sync *(trakt)* | Watchlist → Radarr/Sonarr | — |
| Trakt Cleanup *(trakt)* | Radarr/Sonarr deletes → Trakt | 5000 |

---

## Custom Scripts

Two Tautulli notification scripts live in `tautulliScripts/`:

**`trakt_scrobbler.py`** — scrobbles play/pause/stop events to Trakt. Marks items as watched at 80% progress.

**`plex_progressive_downloader.py`** — pre-fetches episodes as you watch. At 50% through a season it downloads the next one. At the last available episode it enables monitoring for all seasons.

`configure.sh` copies both scripts to `config/tautulli/scripts/` and patches all credentials in-place. Three manual steps remain:

1. **Connect Tautulli to Plex** — Settings → Plex Media Server, hostname `plex`, port `32400`, Verify Server, Fetch New Token, Save.
2. **Add notification agents** — two Script agents in Tautulli UI (Trakt Scrobbler + Progressive Downloader). Full walkthrough in SETUP.md.
3. **Trakt scrobbler OAuth** — `configure.sh` walks you through this interactively once Tautulli is connected to Plex.

---

## Storage

Two configurations, both set in `.env`:

**Single drive** — downloads and library share one drive:
```
MEDIA_DIR=/srv/media        → /media  (library — Radarr/Sonarr root folders point here)
DOWNLOADS_DIR=/srv/downloads → /downloads  (download client drops files here)
```
Radarr/Sonarr hardlink on import — instant, zero copy overhead.

**SSD + HDD** — fast downloads, large library:
```
MEDIA_DIR=/mnt/hdd/media    → /media
DOWNLOADS_DIR=/mnt/ssd      → /downloads
```
Radarr/Sonarr copy on import (cross-filesystem). The SSD is purely a staging area — once imported, files live on the HDD.

---

## Configuration

All credentials, paths, and network settings live in `.env`. See `.env.example` for the full reference with descriptions.

See [SETUP.md](SETUP.md) for the complete setup walkthrough.
