#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Trakt Scrobbler for Tautulli - Fixed Version

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

Setup in Tautulli:
1. Settings > Notification Agents > Scripts > Add a new notification agent
2. Configuration:
   - Script Folder: /path/to/this/script/
   - Script File: trakt_scrobbler.py
3. Triggers:
   - Playback Start: ✓
   - Playback Stop: ✓
   - Playback Pause: ✓
   - Playback Resume: ✓
4. Conditions:
   - Media Type: movie, episode
5. Arguments:
   --action {action} --user {username} --title "{title}" --year {year} --progress {progress_percent} --duration {duration} --show_name "{show_name}" --season_num {season_num} --episode_num {episode_num} --tmdb_id {tmdb_id} --tvdb_id {thetvdb_id} --imdb_id {imdb_id}

Required Trakt.tv API Setup:
1. Go to https://trakt.tv/oauth/applications/new
2. Create a new app with redirect URI: urn:ietf:wg:oauth:2.0:oob
3. Get Client ID and Client Secret
4. Run script with --setup flag to authenticate
"""

import requests
import json
import sys
import os
import argparse
import time
from datetime import datetime, timezone

# ## CONFIGURATION - EDIT THESE SETTINGS ##
TRAKT_CLIENT_ID = '6a329068fe5503480ceaeb5477493a75f7230a457834a0e3f3c0704e7ad0a7fc'        # Get from https://trakt.tv/oauth/applications
TRAKT_CLIENT_SECRET = 'b278d963bf8e729b6c9d0cb52b1c651c1fb8d08ccd54bd6c0fc92da8df81f263' # Get from https://trakt.tv/oauth/applications
TRAKT_REDIRECT_URI = 'urn:ietf:wg:oauth:2.0:oob'

# Tautulli API configuration
TAUTULLI_URL = 'http://tautulli:8181'
TAUTULLI_API_KEY = '5c7bdfb1ff274ef59f74df5d2bc6009c'

# File to store access tokens (will be created automatically)
TOKEN_FILE = './trakt_tokens.json'

# File to store last scrobbled episode state
STATE_FILE = './trakt_scrobbler_state.json'

# Minimum watch percentage to mark as "watched" (90% = 0.9)
WATCH_THRESHOLD = 0.9

# Enable debug logging
VERBOSE_LOGGING = True

def get_session_from_tautulli(rating_key):
    """
    Fetch current session data from Tautulli API
    Returns session data with correct progress and session_id
    """
    try:
        url = f"{TAUTULLI_URL}/api/v2"
        params = {
            'apikey': TAUTULLI_API_KEY,
            'cmd': 'get_activity'
        }
        
        log(f"Fetching session data from Tautulli API for rating_key {rating_key}")
        response = requests.get(url, params=params, timeout=10)
        
        if response.status_code != 200:
            log(f"Tautulli API error: {response.status_code}", error=True)
            return None
        
        data = response.json()
        if data.get('response', {}).get('result') != 'success':
            log(f"Tautulli API returned error: {data}", error=True)
            return None
        
        # Find the session matching our rating_key
        sessions = data.get('response', {}).get('data', {}).get('sessions', [])
        for session in sessions:
            if str(session.get('rating_key')) == str(rating_key):
                log(f"Found matching session: progress={session.get('progress_percent')}%, session_id={session.get('session_id')}")
                return {
                    'progress': float(session.get('progress_percent', 0)),
                    'session_id': session.get('session_id', ''),
                    'duration': session.get('duration', 0)
                }
        
        log(f"No active session found for rating_key {rating_key}", error=True)
        return None
        
    except Exception as e:
        log(f"Error fetching from Tautulli API: {e}", error=True)
        return None

def log(message, error=False):
    """Print log message for Tautulli logging"""
    if VERBOSE_LOGGING or error:
        output = sys.stderr if error else sys.stdout
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        output.write(f"[{timestamp}] [Trakt Scrobbler] {message}\n")

def normalize_progress(progress):
    """
    Normalize progress to be within valid range for Trakt API
    - Progress must be between 0-100
    - For pause, progress must be >= 1.0
    - Progress > 100 indicates episode transition (Tautulli quirk)
    """
    progress = float(progress)
    
    # Progress > 100% means new episode just started (Tautulli quirk)
    if progress > 100:
        log(f"Progress {progress}% exceeds 100%, resetting to 0% (new episode started)")
        progress = 0.0
    
    # Floor at 0%
    if progress < 0:
        log(f"Progress {progress}% is negative, setting to 0%")
        progress = 0.0
    
    return progress

def load_state():
    """Load last scrobbled state from file"""
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE, 'r') as f:
                return json.load(f)
    except Exception as e:
        log(f"Error loading state: {e}", error=True)
    return {}

def save_state(session_id, show_name, season_num, episode_num, action, progress):
    """Save current scrobble state to file"""
    try:
        state = load_state()
        if not session_id:
            log("Cannot save state: session_id is empty", error=True)
            return

        state[session_id] = {
            'show_name': show_name,
            'season_num': season_num,
            'episode_num': episode_num,
            'action': action,
            'progress': progress,
            'timestamp': int(time.time())
        }

        # Clean up old sessions (older than 24 hours)
        current_time = int(time.time())
        state = {k: v for k, v in state.items() if current_time - v.get('timestamp', 0) < 86400}

        with open(STATE_FILE, 'w') as f:
            json.dump(state, f, indent=2)
        log(f"State saved: session_id={session_id}, S{season_num:02d}E{episode_num:02d}, action={action}, progress={progress}%")
    except Exception as e:
        log(f"Error saving state: {e}", error=True)

def is_new_episode(session_id, show_name, season_num, episode_num):
    """Check if this is a new episode compared to last scrobbled state"""
    if not session_id:
        log("Cannot check episode change: session_id is empty")
        return False

    state = load_state()
    last_state = state.get(session_id)

    if not last_state:
        log(f"No previous state found for session_id {session_id}, treating as new episode")
        return True

    last_show = last_state.get('show_name')
    last_season = last_state.get('season_num')
    last_episode = last_state.get('episode_num')

    # For TV shows, compare show/season/episode
    if show_name and season_num is not None and episode_num is not None:
        is_different = (last_show != show_name or
                       last_season != season_num or
                       last_episode != episode_num)

        if is_different:
            log(f"Episode changed: {last_show} S{last_season:02d}E{last_episode:02d} -> {show_name} S{season_num:02d}E{episode_num:02d}")
            return True
        else:
            log(f"Same episode: {show_name} S{season_num:02d}E{episode_num:02d}")
            return False

    return False

def load_tokens():
    """Load access tokens from file"""
    try:
        if os.path.exists(TOKEN_FILE):
            with open(TOKEN_FILE, 'r') as f:
                return json.load(f)
    except Exception as e:
        log(f"Error loading tokens: {e}", error=True)
    return None

def save_tokens(tokens):
    """Save access tokens to file"""
    try:
        os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
        with open(TOKEN_FILE, 'w') as f:
            json.dump(tokens, f, indent=2)
        log("Tokens saved successfully")
    except Exception as e:
        log(f"Error saving tokens: {e}", error=True)

def get_device_code():
    """Get device code for authentication"""
    url = 'https://api.trakt.tv/oauth/device/code'
    data = {'client_id': TRAKT_CLIENT_ID}
    headers = {'Content-Type': 'application/json'}
    
    try:
        response = requests.post(url, json=data, headers=headers)
        return response.json()
    except Exception as e:
        log(f"Error getting device code: {e}", error=True)
        return None

def get_access_token(device_code, interval):
    """Poll for access token"""
    url = 'https://api.trakt.tv/oauth/device/token'
    data = {
        'code': device_code,
        'client_id': TRAKT_CLIENT_ID,
        'client_secret': TRAKT_CLIENT_SECRET
    }
    headers = {'Content-Type': 'application/json'}
    
    max_attempts = 60  # 5 minutes max
    attempts = 0
    
    while attempts < max_attempts:
        try:
            response = requests.post(url, json=data, headers=headers)
            log(f"Polling attempt {attempts + 1}, status: {response.status_code}")
            
            # Check if response has content
            if not response.text:
                log("Empty response, retrying...")
                time.sleep(interval)
                attempts += 1
                continue
            
            # Try to parse JSON
            try:
                result = response.json()
            except json.JSONDecodeError as e:
                log(f"JSON decode error: {e}, response: {response.text[:100]}")
                time.sleep(interval)
                attempts += 1
                continue
            
            if response.status_code == 200:
                log("Authentication successful!")
                return result
            elif result.get('error') == 'authorization_pending':
                log("Authorization pending, waiting...")
                time.sleep(interval)
                attempts += 1
            elif result.get('error') == 'slow_down':
                log("Rate limited, slowing down...")
                time.sleep(interval + 1)
                attempts += 1
            else:
                log(f"Token error: {result}", error=True)
                return None
        except requests.RequestException as e:
            log(f"Request error: {e}", error=True)
            time.sleep(interval)
            attempts += 1
        except Exception as e:
            log(f"Unexpected error polling for token: {e}", error=True)
            time.sleep(interval)
            attempts += 1
    
    log("Token polling timeout", error=True)
    return None

def refresh_access_token(refresh_token):
    """Refresh expired access token"""
    url = 'https://api.trakt.tv/oauth/token'
    data = {
        'refresh_token': refresh_token,
        'client_id': TRAKT_CLIENT_ID,
        'client_secret': TRAKT_CLIENT_SECRET,
        'redirect_uri': TRAKT_REDIRECT_URI,
        'grant_type': 'refresh_token'
    }
    headers = {'Content-Type': 'application/json'}
    
    try:
        response = requests.post(url, json=data, headers=headers)
        if response.status_code == 200:
            return response.json()
        else:
            log(f"Token refresh failed: {response.status_code} {response.text}", error=True)
            return None
    except Exception as e:
        log(f"Error refreshing token: {e}", error=True)
        return None

def get_valid_token():
    """Get a valid access token, refreshing if necessary"""
    tokens = load_tokens()
    if not tokens:
        log("No tokens found. Please run with --setup flag first.", error=True)
        return None
    
    # Check if token is expired (with 10 minute buffer)
    expires_at = tokens.get('created_at', 0) + tokens.get('expires_in', 0) - 600
    if time.time() > expires_at:
        log("Token expired, refreshing...")
        new_tokens = refresh_access_token(tokens.get('refresh_token'))
        if new_tokens:
            new_tokens['created_at'] = int(time.time())
            save_tokens(new_tokens)
            return new_tokens.get('access_token')
        else:
            log("Token refresh failed. Please re-authenticate with --setup.", error=True)
            return None
    
    return tokens.get('access_token')

def make_trakt_request(endpoint, method='GET', data=None, ignore_409=False):
    """Make authenticated request to Trakt API"""
    access_token = get_valid_token()
    if not access_token:
        return None
    
    url = f'https://api.trakt.tv/{endpoint}'
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': TRAKT_CLIENT_ID
    }
    
    try:
        log(f"Making {method} request to {url}")
        if data:
            log(f"Request data: {json.dumps(data, indent=2)}")
            
        if method == 'GET':
            response = requests.get(url, headers=headers)
        elif method == 'POST':
            response = requests.post(url, json=data, headers=headers)
        else:
            log(f"Unsupported method: {method}", error=True)
            return None
        
        log(f"Response status: {response.status_code}")
        log(f"Response headers: {dict(response.headers)}")
        log(f"Response body: {response.text}")
        
        # Handle 409 Conflict - item already scrobbled/watched
        if response.status_code == 409:
            if ignore_409:
                log("409 Conflict ignored (item already scrobbled)")
                return {"ignored": True, "status": 409}
            else:
                log(f"Trakt API error: {response.status_code} {response.text}", error=True)
                return None
        
        # Handle successful responses
        if response.status_code in [200, 201, 204]:
            if response.text:
                result = response.json()
                log(f"API call successful: {result}")
                return result
            else:
                log("API call successful (no content)")
                return {"success": True}
        
        # Handle error responses
        log(f"Trakt API error: {response.status_code} {response.text}", error=True)
        return None
            
    except requests.RequestException as e:
        log(f"Request error: {e}", error=True)
        return None
    except json.JSONDecodeError as e:
        log(f"JSON decode error: {e}", error=True)
        return None
    except Exception as e:
        log(f"Unexpected error: {e}", error=True)
        return None

def safe_int(value):
    """Safely convert value to int"""
    if value is None or value == '{tmdb_id}' or value == '{thetvdb_id}':
        return None
    try:
        return int(value)
    except (ValueError, TypeError):
        return None

def safe_str(value):
    """Safely convert value to string"""
    if value is None or value == '{imdb_id}':
        return None
    return str(value).strip()

def build_media_object(title, year, tmdb_id=None, imdb_id=None, tvdb_id=None,
                      show_name=None, season_num=None, episode_num=None):
    """Build media object for Trakt API"""
    media_object = {}
    
    if show_name and season_num is not None and episode_num is not None:
        # TV Episode
        media_object["show"] = {
            "title": show_name,
            "ids": {}
        }
        
        if year:
            media_object["show"]["year"] = year
        
        # Add show IDs
        tvdb_val = safe_int(tvdb_id)
        if tvdb_val:
            media_object["show"]["ids"]["tvdb"] = tvdb_val
            
        imdb_val = safe_str(imdb_id)
        if imdb_val:
            media_object["show"]["ids"]["imdb"] = imdb_val
        
        media_object["episode"] = {
            "season": season_num,
            "number": episode_num
        }
    else:
        # Movie
        media_object["movie"] = {
            "title": title,
            "ids": {}
        }
        
        if year:
            media_object["movie"]["year"] = year
        
        # Add movie IDs
        tmdb_val = safe_int(tmdb_id)
        if tmdb_val:
            media_object["movie"]["ids"]["tmdb"] = tmdb_val
            
        imdb_val = safe_str(imdb_id)
        if imdb_val:
            media_object["movie"]["ids"]["imdb"] = imdb_val
    
    return media_object

def scrobble_start(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                  show_name=None, season_num=None, episode_num=None, session_id=None, rating_key=None):
    """Scrobble start watching"""

    original_progress = progress
    fetched_session_id = session_id

    # If session_id is empty, wait and fetch fresh data from Tautulli
    if not session_id or session_id == '':
        log("session_id is empty, waiting 10 seconds for Tautulli to update session...")
        time.sleep(10)

        if rating_key:
            session_data = get_session_from_tautulli(rating_key)
            if session_data:
                progress = session_data['progress']
                fetched_session_id = session_data['session_id']
                log(f"Fetched fresh data from Tautulli: progress={progress}%, session_id={fetched_session_id}")
            else:
                log("Failed to fetch session data, using original values", error=True)
        else:
            log("No rating_key provided, cannot fetch from Tautulli API", error=True)

    # For TV episodes, check if this is a new episode
    if show_name and season_num is not None and episode_num is not None and fetched_session_id:
        if is_new_episode(fetched_session_id, show_name, season_num, episode_num):
            log(f"New episode detected! Resetting progress from {progress}% to 0%")
            progress = 0.0
        else:
            # Same episode - normalize progress normally
            progress = normalize_progress(progress)
            # If progress is suspiciously high (>90%) when resuming same episode, cap it
            if progress > 90 and original_progress != progress:
                log(f"Progress {progress}% seems too high for episode continuation, capping at 5%")
                progress = 5.0
    else:
        # No session_id available or not a TV episode, just normalize
        progress = normalize_progress(progress)

    media_object = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id,
                                    show_name, season_num, episode_num)

    data = {
        "progress": progress,
        **media_object
    }

    log(f"Scrobbling start: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/start', 'POST', data)

    if result:
        log("Successfully scrobbled start")
        # Save state after successful scrobble
        if fetched_session_id:
            save_state(fetched_session_id, show_name, season_num, episode_num, 'start', progress)
        return True
    else:
        log("Failed to scrobble start", error=True)
        return False

def scrobble_pause(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                  show_name=None, season_num=None, episode_num=None, session_id=None):
    """Scrobble pause watching"""
    # Normalize progress
    progress = normalize_progress(progress)

    # Trakt requires progress >= 1.0 to pause
    if progress < 1.0:
        log(f"Progress {progress}% is below 1.0%, skipping pause (Trakt requirement)")
        return True  # Return True to avoid error in Tautulli

    media_object = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id,
                                    show_name, season_num, episode_num)

    data = {
        "progress": progress,
        **media_object
    }

    log(f"Scrobbling pause: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/pause', 'POST', data)

    if result:
        log("Successfully scrobbled pause")
        # Save state after successful scrobble
        if session_id:
            save_state(session_id, show_name, season_num, episode_num, 'pause', progress)
        return True
    else:
        log("Failed to scrobble pause", error=True)
        return False

def scrobble_stop(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                 show_name=None, season_num=None, episode_num=None, session_id=None):
    """Scrobble stop watching"""
    # Normalize progress
    progress = normalize_progress(progress)

    # Always save state first for episode tracking, even if Trakt API call fails
    # This ensures accurate episode change detection on next play
    if session_id and show_name and season_num is not None and episode_num is not None:
        save_state(session_id, show_name, season_num, episode_num, 'stop', progress)

    # Skip Trakt API call if progress is too low (Trakt requires >= 1% for stop)
    if progress < 1.0:
        log(f"Progress {progress}% is below 1.0%, skipping Trakt stop (not enough watched)")
        return True  # Return True to avoid error in Tautulli

    media_object = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id,
                                    show_name, season_num, episode_num)

    data = {
        "progress": progress,
        **media_object
    }

    log(f"Scrobbling stop: {json.dumps(data, indent=2)}")
    # Ignore 409 conflicts (already watched/scrobbled)
    result = make_trakt_request('scrobble/stop', 'POST', data, ignore_409=True)

    if result:
        # Check if it was a 409 that we ignored
        if result.get("ignored") and result.get("status") == 409:
            log("Stop already processed (409 conflict ignored)")
        else:
            log("Successfully scrobbled stop")

        # If watched more than threshold, mark as watched
        if progress >= (WATCH_THRESHOLD * 100):
            log(f"Progress {progress}% >= threshold {WATCH_THRESHOLD*100}%, marking as watched")
            return mark_as_watched(title, year, tmdb_id, imdb_id, tvdb_id,
                                 show_name, season_num, episode_num)
        return True
    else:
        log("Failed to scrobble stop", error=True)
        # State was already saved at the beginning, so return True to not fail in Tautulli
        return True

def mark_as_watched(title, year, tmdb_id=None, imdb_id=None, tvdb_id=None,
                   show_name=None, season_num=None, episode_num=None):
    """Mark media as watched"""
    media_object = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id, 
                                    show_name, season_num, episode_num)
    
    if show_name:
        # TV Episode
        endpoint = 'sync/history'
        data = {
            "episodes": [media_object]
        }
    else:
        # Movie
        endpoint = 'sync/history'
        data = {
            "movies": [media_object]
        }
    
    log(f"Marking as watched: {json.dumps(data, indent=2)}")
    result = make_trakt_request(endpoint, 'POST', data)
    
    if result:
        log("Successfully marked as watched")
        return True
    else:
        log("Failed to mark as watched", error=True)
        return False

def setup_authentication():
    """Setup Trakt authentication"""
    log("Setting up Trakt authentication...")
    
    # Get device code
    device_response = get_device_code()
    if not device_response:
        log("Failed to get device code", error=True)
        return False
    
    print(f"\nPlease go to: {device_response['verification_url']}")
    print(f"And enter this code: {device_response['user_code']}")
    print("Waiting for authentication...")
    
    # Wait a moment for user to enter code before starting to poll
    log("Waiting 5 seconds before starting to poll...")
    time.sleep(5)
    
    # Poll for token
    tokens = get_access_token(device_response['device_code'], device_response['interval'])
    if tokens:
        tokens['created_at'] = int(time.time())
        save_tokens(tokens)
        log("Authentication successful!")
        return True
    else:
        log("Authentication failed", error=True)
        return False

def test_trakt_connection():
    """Test Trakt API connection and authentication"""
    log("Testing Trakt API connection...")

    # Test basic user info
    result = make_trakt_request('users/settings')
    if result:
        username = result.get('user', {}).get('username', 'Unknown')
        log(f"Successfully connected to Trakt as user: {username}")
        return True
    else:
        log("Failed to connect to Trakt API", error=True)
        return False

def safe_year(value):
    """Safely parse year from string, returning None for empty/invalid values"""
    if not value or value == '':
        return None
    try:
        year = int(value)
        # Basic sanity check for year range
        if 1800 <= year <= 2100:
            return year
        return None
    except (ValueError, TypeError):
        return None

def main():
    parser = argparse.ArgumentParser(description='Trakt Scrobbler for Tautulli')
    parser.add_argument('--setup', action='store_true', help='Setup Trakt authentication')
    parser.add_argument('--test', action='store_true', help='Test Trakt API connection')
    parser.add_argument('--action', help='Tautulli action (play, pause, stop, resume)')
    parser.add_argument('--user', help='Plex username')
    parser.add_argument('--title', help='Media title')
    parser.add_argument('--year', type=safe_year, help='Media year')
    parser.add_argument('--progress', type=float, default=0, help='Playback progress percentage')
    parser.add_argument('--duration', type=int, help='Media duration in seconds')
    parser.add_argument('--show_name', help='TV show name (for episodes)')
    parser.add_argument('--season_num', type=int, help='Season number (for episodes)')
    parser.add_argument('--episode_num', type=int, help='Episode number (for episodes)')
    parser.add_argument('--tmdb_id', help='TMDb ID')
    parser.add_argument('--tvdb_id', help='TheTVDB ID')
    parser.add_argument('--imdb_id', help='IMDb ID')
    parser.add_argument('--session_id', help='Tautulli session ID (unique per stream)')
    parser.add_argument('--rating_key', help='Plex rating key (unique media identifier)')

    args = parser.parse_args()
    
    # Handle setup
    if args.setup:
        return setup_authentication()
    
    # Handle test
    if args.test:
        return test_trakt_connection()
    
    # Validate required arguments
    if not args.action:
        log("No action specified", error=True)
        return False
    
    if not args.title:
        log("No title specified", error=True)
        return False
    
    log(f"Action: {args.action}, Title: {args.title}, Progress: {args.progress}%")
    
    # Handle different actions
    try:
        if args.action in ['play', 'resume']:
            return scrobble_start(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num,
                args.session_id, args.rating_key
            )
        elif args.action == 'pause':
            return scrobble_pause(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num,
                args.session_id
            )
        elif args.action == 'stop':
            return scrobble_stop(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num,
                args.session_id
            )
        else:
            log(f"Unknown action: {args.action}", error=True)
            return False
    except Exception as e:
        log(f"Error processing action: {e}", error=True)
        return False

if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)