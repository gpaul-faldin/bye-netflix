# Install Checklist

---

## Initial Setup

- [ ] Ran `./setup.sh` — answered all prompts
- [ ] `.env` and `start.sh` generated
- [ ] `./start.sh` — stack is up

---

## VPN *(if enabled)*

- [ ] `.ovpn` file placed at `config/gluetun/vpn.ovpn`
- [ ] `docker exec gluetun wget -qO- https://ifconfig.me` returns VPN IP

---

## Plex

- [ ] Plex claim token set in `.env` → server linked to Plex account
- [ ] Media libraries created pointing to `/media` and/or `/storage`

---

## Prowlarr → Radarr + Sonarr

- [ ] Radarr connected in Prowlarr (Settings → Apps)
- [ ] Sonarr connected in Prowlarr (Settings → Apps)
- [ ] At least one indexer added and synced

---

## Radarr + Sonarr

- [ ] Root folders set (`/media/movies`, `/media/tv`)
- [ ] Download client(s) added (Deluge and/or SABnzbd)
- [ ] API keys copied to `.env` → stack restarted

---

## Trakt *(if enabled)*

- [ ] OAuth completed: `docker compose ... run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup`
- [ ] Token file exists: `config/trakt-watchlist-sync/trakt_tokens.json`
- [ ] Radarr webhook → `http://trakt-watchlist-cleanup:5000/radarr` (On Movie Delete)
- [ ] Sonarr webhook → `http://trakt-watchlist-cleanup:5000/sonarr` (On Series Delete)

---

## Tautulli Scripts *(optional)*

- [ ] Scripts copied to `config/tautulli/scripts/`
- [ ] API keys updated in both scripts
- [ ] Scrobbler OAuth completed: `docker exec -it tautulli python /scripts/trakt_scrobbler.py --setup`
- [ ] Scrobbler notification agent configured (triggers: Start, Stop, Pause, Resume)
- [ ] Progressive downloader notification agent configured (trigger: Start, episodes only)
- [ ] Tautulli connected to Plex server

---

## Supporting Services

- [ ] Fetcharr: `config/fetcharr/config.yml` updated with API keys
- [ ] Bazarr: connected to Radarr + Sonarr, subtitle providers configured

---

## End-to-End Test

- [ ] Add a movie to Trakt watchlist → appears in Radarr within 20s
- [ ] Add a show to Trakt watchlist → appears in Sonarr within 20s
- [ ] Play something in Plex → scrobble appears on Trakt
- [ ] Delete from Radarr → removed from Trakt watchlist
- [ ] Watch an episode → next episodes queued by progressive downloader
