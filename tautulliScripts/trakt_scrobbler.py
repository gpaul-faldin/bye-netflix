#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Trakt Scrobbler for Tautulli

Handles scrobbling to Trakt.tv for:
- Movies: start, pause, stop (with progress tracking)
- TV Episodes: start, pause, stop (with progress tracking)

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

# File to store access tokens (will be created automatically)
TOKEN_FILE = './trakt_tokens.json'

# Minimum watch percentage to mark as "watched" (80% = 0.8)
WATCH_THRESHOLD = 0.8

# Enable debug logging
VERBOSE_LOGGING = True

def log(message, error=False):
    """Print log message for Tautulli logging"""
    if VERBOSE_LOGGING or error:
        output = sys.stderr if error else sys.stdout
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        output.write(f"[{timestamp}] [Trakt Scrobbler] {message}\n")

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

def make_trakt_request(endpoint, method='GET', data=None):
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
        
        if response.text:
            log(f"Response body: {response.text}")
        
        if response.status_code == 204:  # No content (success for some endpoints)
            log("API call successful (204 No Content)")
            return {}
        elif response.status_code == 200 or response.status_code == 201:
            result = response.json()
            log(f"API call successful: {result}")
            return result
        else:
            log(f"Trakt API error: {response.status_code} {response.text}", error=True)
            return None
    except Exception as e:
        log(f"Error making Trakt request: {e}", error=True)
        return None

def build_media_object(title, year, tmdb_id=None, imdb_id=None, tvdb_id=None, 
                      show_name=None, season_num=None, episode_num=None):
    """Build media object for Trakt API"""
    
    def safe_int(value):
        """Safely convert to int, return None if invalid"""
        if not value or str(value).strip() == '' or str(value).startswith('{'):
            return None
        try:
            val = int(str(value).strip())
            return val if val > 0 else None
        except (ValueError, TypeError):
            return None
    
    def safe_str(value):
        """Safely get string value, return None if invalid"""
        if not value or str(value).strip() == '' or str(value).startswith('{'):
            return None
        return str(value).strip()
    
    if show_name and season_num and episode_num:
        # TV Episode
        media_object = {
            "show": {
                "title": show_name,
                "ids": {}
            },
            "episode": {
                "season": int(season_num),
                "number": int(episode_num)
            }
        }
        
        # Add year if valid
        if year and year > 1900:
            media_object["show"]["year"] = year
        
        # Add show IDs
        tmdb_val = safe_int(tmdb_id)
        if tmdb_val:
            media_object["show"]["ids"]["tmdb"] = tmdb_val
            
        tvdb_val = safe_int(tvdb_id)
        if tvdb_val:
            media_object["show"]["ids"]["tvdb"] = tvdb_val
            
        imdb_val = safe_str(imdb_id)
        if imdb_val:
            media_object["show"]["ids"]["imdb"] = imdb_val
            
    else:
        # Movie
        media_object = {
            "movie": {
                "title": title,
                "ids": {}
            }
        }
        
        # Add year if valid
        if year and year > 1900:
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
                  show_name=None, season_num=None, episode_num=None):
    """Scrobble start watching"""
    media_object = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id, 
                                    show_name, season_num, episode_num)
    
    data = {
        "progress": float(progress),
        **media_object
    }
    
    log(f"Scrobbling start: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/start', 'POST', data)
    
    if result:
        log("Successfully scrobbled start")
        return True
    else:
        log("Failed to scrobble start", error=True)
        return False

def scrobble_pause(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                  show_name=None, season_num=None, episode_num=None):
    """Scrobble pause watching"""
    media_object = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id, 
                                    show_name, season_num, episode_num)
    
    data = {
        "progress": float(progress),
        **media_object
    }
    
    log(f"Scrobbling pause: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/pause', 'POST', data)
    
    if result:
        log("Successfully scrobbled pause")
        return True
    else:
        log("Failed to scrobble pause", error=True)
        return False

def scrobble_stop(title, year, progress, tmdb_id=None, imdb_id=None, tvdb_id=None,
                 show_name=None, season_num=None, episode_num=None):
    """Scrobble stop watching"""
    media_object = build_media_object(title, year, tmdb_id, imdb_id, tvdb_id, 
                                    show_name, season_num, episode_num)
    
    data = {
        "progress": float(progress),
        **media_object
    }
    
    log(f"Scrobbling stop: {json.dumps(data, indent=2)}")
    result = make_trakt_request('scrobble/stop', 'POST', data)
    
    if result:
        log("Successfully scrobbled stop")
        
        # If watched more than threshold, mark as watched
        if float(progress) >= (WATCH_THRESHOLD * 100):
            log(f"Progress {progress}% >= threshold {WATCH_THRESHOLD*100}%, marking as watched")
            return mark_as_watched(title, year, tmdb_id, imdb_id, tvdb_id, 
                                 show_name, season_num, episode_num)
        return True
    else:
        log("Failed to scrobble stop", error=True)
        return False

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

def main():
    parser = argparse.ArgumentParser(description='Trakt Scrobbler for Tautulli')
    parser.add_argument('--setup', action='store_true', help='Setup Trakt authentication')
    parser.add_argument('--test', action='store_true', help='Test Trakt API connection')
    parser.add_argument('--action', help='Tautulli action (play, pause, stop, resume)')
    parser.add_argument('--user', help='Plex username')
    parser.add_argument('--title', help='Media title')
    parser.add_argument('--year', type=int, help='Media year')
    parser.add_argument('--progress', type=float, default=0, help='Playback progress percentage')
    parser.add_argument('--duration', type=int, help='Media duration in seconds')
    parser.add_argument('--show_name', help='TV show name (for episodes)')
    parser.add_argument('--season_num', type=int, help='Season number (for episodes)')
    parser.add_argument('--episode_num', type=int, help='Episode number (for episodes)')
    parser.add_argument('--tmdb_id', help='TMDb ID')
    parser.add_argument('--tvdb_id', help='TheTVDB ID')
    parser.add_argument('--imdb_id', help='IMDb ID')
    
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
                args.show_name, args.season_num, args.episode_num
            )
        elif args.action == 'pause':
            return scrobble_pause(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num
            )
        elif args.action == 'stop':
            return scrobble_stop(
                args.title, args.year, args.progress,
                args.tmdb_id, args.imdb_id, args.tvdb_id,
                args.show_name, args.season_num, args.episode_num
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