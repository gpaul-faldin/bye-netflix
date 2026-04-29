#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Trakt Scrobbler for Tautulli

Handles scrobbling to Trakt.tv for:
- Movies: start, pause, stop (with progress tracking)
- TV Episodes: start, pause, stop (with progress tracking)

Improvements:
- Detects episode changes by comparing show/season/episode numbers
- Resets progress to 0% when starting a new episode
- Handles progress > 100% by resetting to 0% (Tautulli quirk)
- Skips pause events when progress < 1% (Trakt requirement)
- Ignores 409 conflicts on stop (already scrobbled)
- Better error handling for episode transitions
- Uses only stdlib (urllib) — no external packages required

Setup in Tautulli:
1. Settings > Notification Agents > Scripts > Add a new notification agent
2. Configuration:
   - Script Folder: /scripts
   - Script File: trakt_scrobbler.py
3. Triggers:
   - Playback Start: ✓
   - Playback Stop: ✓
   - Playback Pause: ✓
   - Playback Resume: ✓
4. Arguments (for each trigger above):
   --action {action} --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id}

Required Trakt.tv API Setup:
1. Go to https://trakt.tv/oauth/applications/new
2. Create a new app with redirect URI: urn:ietf:wg:oauth:2.0:oob
3. Get Client ID and Client Secret
4. Run script with --setup flag to authenticate
"""

import json
import sys
import os
import argparse
import time
import urllib.request
import urllib.parse
import urllib.error
from datetime import datetime, timezone

# ## CONFIGURATION - EDIT THESE SETTINGS ##
TRAKT_CLIENT_ID = ''        # Get from https://trakt.tv/oauth/applications
TRAKT_CLIENT_SECRET = ''    # Get from https://trakt.tv/oauth/applications
TRAKT_REDIRECT_URI = 'urn:ietf:wg:oauth:2.0:oob'

# Tautulli API configuration
TAUTULLI_URL = 'http://tautulli:8181'
TAUTULLI_API_KEY = ''

# File to store access tokens (will be created automatically)
TOKEN_FILE = './trakt_tokens.json'

# File to store last scrobbled episode state
STATE_FILE = './trakt_scrobbler_state.json'

# Minimum watch percentage to mark as "watched"
WATCH_THRESHOLD = 0.9

# Enable debug logging
VERBOSE_LOGGING = True


# ─── HTTP helpers (stdlib urllib, no requests needed) ────────────────────────

def _http(url, method='GET', data=None, headers=None, timeout=10):
    """
    Minimal HTTP helper.
    Returns (status_code, response_body_str).
    Raises nothing — caller checks the status.
    """
    if headers is None:
        headers = {}
    if 'User-Agent' not in headers:
        headers['User-Agent'] = 'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0'
    body = json.dumps(data).encode() if data is not None else None
    if body and 'Content-Type' not in headers:
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return 0, str(e)


# ─── Logging ─────────────────────────────────────────────────────────────────

def log(message, error=False):
    if VERBOSE_LOGGING or error:
        out = sys.stderr if error else sys.stdout
        ts  = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        out.write(f"[{ts}] [Trakt Scrobbler] {message}\n")


# ─── Progress helpers ─────────────────────────────────────────────────────────

def normalize_progress(progress):
    progress = float(progress)
    if progress > 100:
        log(f"Progress {progress}% exceeds 100%, resetting to 0% (new episode started)")
        return 0.0
    if progress < 0:
        return 0.0
    return progress


# ─── State file ──────────────────────────────────────────────────────────────

def load_state():
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE) as f:
                return json.load(f)
    except Exception as e:
        log(f"Error loading state: {e}", error=True)
    return {}


def save_state(session_id, show_name, season_num, episode_num, action, progress):
    try:
        if not session_id:
            log("Cannot save state: session_id is empty", error=True)
            return
        state = load_state()
        state[session_id] = {
            'show_name':   show_name,
            'season_num':  season_num,
            'episode_num': episode_num,
            'action':      action,
            'progress':    progress,
            'timestamp':   int(time.time()),
        }
        # Prune sessions older than 24 h
        now = int(time.time())
        state = {k: v for k, v in state.items() if now - v.get('timestamp', 0) < 86400}
        with open(STATE_FILE, 'w') as f:
            json.dump(state, f, indent=2)
        log(f"State saved: session_id={session_id}, S{season_num:02d}E{episode_num:02d}, "
            f"action={action}, progress={progress}%")
    except Exception as e:
        log(f"Error saving state: {e}", error=True)


def is_new_episode(session_id, show_name, season_num, episode_num):
    if not session_id:
        return False
    last = load_state().get(session_id)
    if not last:
        return True
    if show_name and season_num is not None and episode_num is not None:
        changed = (last.get('show_name') != show_name or
                   last.get('season_num') != season_num or
                   last.get('episode_num') != episode_num)
        if changed:
            log(f"Episode changed: {last.get('show_name')} "
                f"S{last.get('season_num'):02d}E{last.get('episode_num'):02d} → "
                f"{show_name} S{season_num:02d}E{episode_num:02d}")
        return changed
    return False


# ─── Token management ────────────────────────────────────────────────────────

def load_tokens():
    try:
        if os.path.exists(TOKEN_FILE):
            with open(TOKEN_FILE) as f:
                return json.load(f)
    except Exception as e:
        log(f"Error loading tokens: {e}", error=True)
    return None


def save_tokens(tokens):
    try:
        os.makedirs(os.path.dirname(os.path.abspath(TOKEN_FILE)), exist_ok=True)
        with open(TOKEN_FILE, 'w') as f:
            json.dump(tokens, f, indent=2)
        log("Tokens saved successfully")
    except Exception as e:
        log(f"Error saving tokens: {e}", error=True)


def refresh_access_token(refresh_token):
    status, body = _http(
        'https://api.trakt.tv/oauth/token',
        method='POST',
        data={
            'refresh_token': refresh_token,
            'client_id':     TRAKT_CLIENT_ID,
            'client_secret': TRAKT_CLIENT_SECRET,
            'redirect_uri':  TRAKT_REDIRECT_URI,
            'grant_type':    'refresh_token',
        },
    )
    if status == 200:
        return json.loads(body)
    log(f"Token refresh failed: {status} {body}", error=True)
    return None


def get_valid_token():
    tokens = load_tokens()
    if not tokens:
        log("No tokens found. Please run with --setup flag first.", error=True)
        return None
    expires_at = tokens.get('created_at', 0) + tokens.get('expires_in', 0) - 600
    if time.time() > expires_at:
        log("Token expired, refreshing...")
        new_tokens = refresh_access_token(tokens.get('refresh_token'))
        if new_tokens:
            new_tokens['created_at'] = int(time.time())
            save_tokens(new_tokens)
            return new_tokens.get('access_token')
        log("Token refresh failed. Please re-authenticate with --setup.", error=True)
        return None
    return tokens.get('access_token')


# ─── Tautulli helper ─────────────────────────────────────────────────────────

def get_session_from_tautulli(rating_key):
    url = (f"{TAUTULLI_URL}/api/v2?"
           f"apikey={urllib.parse.quote(TAUTULLI_API_KEY)}&cmd=get_activity")
    log(f"Fetching session data from Tautulli for rating_key {rating_key}")
    status, body = _http(url, timeout=10)
    if status != 200:
        log(f"Tautulli API error: {status}", error=True)
        return None
    try:
        data = json.loads(body)
    except Exception:
        log("Tautulli returned non-JSON", error=True)
        return None
    if data.get('response', {}).get('result') != 'success':
        log(f"Tautulli API returned error: {data}", error=True)
        return None
    sessions = data.get('response', {}).get('data', {}).get('sessions', [])
    for s in sessions:
        if str(s.get('rating_key')) == str(rating_key):
            log(f"Found session: progress={s.get('progress_percent')}%, "
                f"session_id={s.get('session_id')}")
            return {
                'progress':   float(s.get('progress_percent', 0)),
                'session_id': s.get('session_id', ''),
                'duration':   s.get('duration', 0),
            }
    log(f"No active session found for rating_key {rating_key}", error=True)
    return None


# ─── Trakt API ────────────────────────────────────────────────────────────────

def make_trakt_request(endpoint, method='GET', data=None, ignore_409=False):
    access_token = get_valid_token()
    if not access_token:
        return None

    url = f'https://api.trakt.tv/{endpoint}'
    headers = {
        'Authorization':    f'Bearer {access_token}',
        'Content-Type':     'application/json',
        'trakt-api-version': '2',
        'trakt-api-key':    TRAKT_CLIENT_ID,
    }
    log(f"Making {method} request to {url}")
    if data:
        log(f"Request data: {json.dumps(data, indent=2)}")

    status, body = _http(url, method=method, data=data, headers=headers)
    log(f"Response status: {status}")
    log(f"Response body: {body}")

    if status == 409:
        if ignore_409:
            log("409 Conflict ignored (item already scrobbled)")
            return {"ignored": True, "status": 409}
        log(f"Trakt API error: 409 {body}", error=True)
        return None

    if status in (200, 201, 204):
        if body:
            try:
                result = json.loads(body)
                log(f"API call successful: {result}")
                return result
            except Exception:
                pass
        log("API call successful (no content)")
        return {"success": True}

    log(f"Trakt API error: {status} {body}", error=True)
    return None


# ─── Media object builder ─────────────────────────────────────────────────────

def safe_int(value):
    if value is None or str(value).startswith('{'):
        return None
    try:
        return int(value)
    except (ValueError, TypeError):
        return None


def safe_str(value):
    if value is None or str(value).startswith('{'):
        return None
    return str(value).strip() or None


def safe_year(value):
    if not value or value == '':
        return None
    try:
        y = int(value)
        return y if 1800 <= y <= 2100 else None
    except (ValueError, TypeError):
        return None


def build_media_object(title, year, tmdb_id=None, imdb_id=None, tvdb_id=None,
                       show_name=None, season_num=None, episode_num=None):
    if show_name and season_num is not None and episode_num is not None:
        obj = {"show": {"title": show_name, "ids": {}}, "episode": {"season": season_num, "number": episode_num}}
        if year:
            obj["show"]["year"] = year
        if safe_int(tvdb_id):
            obj["show"]["ids"]["tvdb"] = safe_int(tvdb_id)
        if safe_str(imdb_id):
            obj["show"]["ids"]["imdb"] = safe_str(imdb_id)
    else:
        obj = {"movie": {"title": title, "ids": {}}}
        if year:
            obj["movie"]["year"] = year
        if safe_int(tmdb_id):
            obj["movie"]["ids"]["tmdb"] = safe_int(tmdb_id)
        if safe_str(imdb_id):
            obj["movie"]["ids"]["imdb"] = safe_str(imdb_id)
    return obj


# ─── Scrobble actions ─────────────────────────────────────────────────────────

def scrobble_start(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                   show_name=None, season_num=None, episode_num=None,
                   session_id=None, rating_key=None):
    original_progress  = progress
    fetched_session_id = session_id

    if not session_id:
        log("session_id empty, waiting 10 s for Tautulli to update session...")
        time.sleep(10)
        if rating_key:
            sd = get_session_from_tautulli(rating_key)
            if sd:
                progress           = sd['progress']
                fetched_session_id = sd['session_id']
                log(f"Fetched from Tautulli: progress={progress}%, "
                    f"session_id={fetched_session_id}")
            else:
                log("Failed to fetch session data, using original values", error=True)

    if show_name and season_num is not None and episode_num is not None and fetched_session_id:
        if is_new_episode(fetched_session_id, show_name, season_num, episode_num):
            log(f"New episode detected — resetting progress from {progress}% to 0%")
            progress = 0.0
        else:
            progress = normalize_progress(progress)
            if progress > 90 and original_progress != progress:
                log(f"Progress {progress}% seems too high for continuation, capping at 5%")
                progress = 5.0
    else:
        progress = normalize_progress(progress)

    data   = {"progress": progress, **build_media_object(title, year, tmdb_id, imdb_id, tvdb_id,
                                                          show_name, season_num, episode_num)}
    log(f"Scrobbling start: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/start', 'POST', data)
    if result:
        log("Successfully scrobbled start")
        if fetched_session_id:
            save_state(fetched_session_id, show_name, season_num, episode_num, 'start', progress)
        return True
    log("Failed to scrobble start", error=True)
    return False


def scrobble_pause(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                   show_name=None, season_num=None, episode_num=None, session_id=None):
    progress = normalize_progress(progress)
    if progress < 1.0:
        log(f"Progress {progress}% < 1.0%, skipping pause (Trakt requirement)")
        return True

    data   = {"progress": progress, **build_media_object(title, year, tmdb_id, imdb_id, tvdb_id,
                                                          show_name, season_num, episode_num)}
    log(f"Scrobbling pause: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/pause', 'POST', data)
    if result:
        log("Successfully scrobbled pause")
        if session_id:
            save_state(session_id, show_name, season_num, episode_num, 'pause', progress)
        return True
    log("Failed to scrobble pause", error=True)
    return False


def scrobble_stop(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                  show_name=None, season_num=None, episode_num=None, session_id=None):
    progress = normalize_progress(progress)

    if session_id and show_name and season_num is not None and episode_num is not None:
        save_state(session_id, show_name, season_num, episode_num, 'stop', progress)

    if progress < 1.0:
        log(f"Progress {progress}% < 1.0%, skipping Trakt stop")
        return True

    data   = {"progress": progress, **build_media_object(title, year, tmdb_id, imdb_id, tvdb_id,
                                                          show_name, season_num, episode_num)}
    log(f"Scrobbling stop: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/stop', 'POST', data, ignore_409=True)
    if result:
        if result.get("ignored") and result.get("status") == 409:
            log("Stop already processed (409 conflict ignored)")
        else:
            log("Successfully scrobbled stop")
        if progress >= (WATCH_THRESHOLD * 100):
            log(f"Progress {progress}% ≥ threshold {WATCH_THRESHOLD*100}%, marking as watched")
            return mark_as_watched(title, year, tmdb_id, imdb_id, tvdb_id,
                                   show_name, season_num, episode_num)
        return True
    log("Failed to scrobble stop", error=True)
    return True  # Don't fail Tautulli trigger on stop errors


def mark_as_watched(title, year, tmdb_id=None, imdb_id=None, tvdb_id=None,
                    show_name=None, season_num=None, episode_num=None):
    obj = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id,
                             show_name, season_num, episode_num)
    data   = {"episodes": [obj]} if show_name else {"movies": [obj]}
    log(f"Marking as watched: {json.dumps(data, indent=2)}")
    result = make_trakt_request('sync/history', 'POST', data)
    if result:
        log("Successfully marked as watched")
        return True
    log("Failed to mark as watched", error=True)
    return False


# ─── Authentication (device code flow) ───────────────────────────────────────

def get_device_code():
    status, body = _http(
        'https://api.trakt.tv/oauth/device/code',
        method='POST',
        data={'client_id': TRAKT_CLIENT_ID},
    )
    if status == 200:
        return json.loads(body)
    log(f"Error getting device code: {status} {body}", error=True)
    return None


def poll_for_token(device_code, interval):
    url  = 'https://api.trakt.tv/oauth/device/token'
    data = {
        'code':          device_code,
        'client_id':     TRAKT_CLIENT_ID,
        'client_secret': TRAKT_CLIENT_SECRET,
    }
    for attempt in range(60):  # up to 5 minutes
        status, body = _http(url, method='POST', data=data)
        log(f"Polling attempt {attempt + 1}, status: {status}")

        if status == 200:
            log("Authentication successful!")
            return json.loads(body)

        if not body:
            time.sleep(interval)
            continue

        try:
            result = json.loads(body)
        except json.JSONDecodeError:
            log(f"Non-JSON response: {body[:100]}")
            time.sleep(interval)
            continue

        err = result.get('error', '')
        if err == 'authorization_pending':
            log("Authorization pending, waiting...")
            time.sleep(interval)
        elif err == 'slow_down':
            log("Rate limited, slowing down...")
            time.sleep(interval + 1)
        else:
            log(f"Token error: {result}", error=True)
            return None

    log("Token polling timeout", error=True)
    return None


def setup_authentication():
    log("Setting up Trakt authentication...")
    device = get_device_code()
    if not device:
        log("Failed to get device code", error=True)
        return False

    print(f"\nPlease go to: {device['verification_url']}")
    print(f"And enter this code: {device['user_code']}")
    print("Waiting for authentication...")
    log("Waiting 5 s before polling...")
    time.sleep(5)

    tokens = poll_for_token(device['device_code'], device['interval'])
    if tokens:
        tokens['created_at'] = int(time.time())
        save_tokens(tokens)
        log("Authentication successful!")
        return True
    log("Authentication failed", error=True)
    return False


def test_trakt_connection():
    log("Testing Trakt API connection...")
    result = make_trakt_request('users/settings')
    if result:
        username = result.get('user', {}).get('username', 'Unknown')
        log(f"Connected to Trakt as: {username}")
        return True
    log("Failed to connect to Trakt API", error=True)
    return False


# ─── Entry point ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Trakt Scrobbler for Tautulli')
    parser.add_argument('--setup',       action='store_true')
    parser.add_argument('--test',        action='store_true')
    parser.add_argument('--action',      help='play | pause | stop | resume')
    parser.add_argument('--user')
    parser.add_argument('--title')
    parser.add_argument('--year',        type=safe_year)
    parser.add_argument('--progress',    type=float, default=0)
    parser.add_argument('--duration',    type=int)
    parser.add_argument('--show_name')
    parser.add_argument('--season_num',  type=int)
    parser.add_argument('--episode_num', type=int)
    parser.add_argument('--tmdb_id')
    parser.add_argument('--tvdb_id')
    parser.add_argument('--imdb_id')
    parser.add_argument('--session_id')
    parser.add_argument('--rating_key')
    args = parser.parse_args()

    if args.setup:
        return setup_authentication()
    if args.test:
        return test_trakt_connection()

    if not args.action:
        log("No action specified", error=True)
        return False
    if not args.title:
        log("No title specified", error=True)
        return False

    log(f"Action: {args.action}, Title: {args.title}, Progress: {args.progress}%")

    try:
        if args.action in ('play', 'resume'):
            return scrobble_start(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num,
                args.session_id, args.rating_key,
            )
        elif args.action == 'pause':
            return scrobble_pause(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num,
                args.session_id,
            )
        elif args.action == 'stop':
            return scrobble_stop(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num,
                args.session_id,
            )
        else:
            log(f"Unknown action: {args.action}", error=True)
            return False
    except Exception as e:
        log(f"Error processing action: {e}", error=True)
        return False


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
