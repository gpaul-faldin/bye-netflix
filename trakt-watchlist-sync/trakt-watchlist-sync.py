#!/usr/bin/env python3
"""
Trakt Watchlist to Radarr/Sonarr Sync Service
Polls Trakt watchlist and automatically adds items to Radarr/Sonarr
"""

import os
import time
import logging
import requests
import json
from datetime import datetime
from typing import List, Dict, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Token management file
TOKEN_FILE = '/config/trakt_tokens.json'


class TraktWatchlistSync:
    def __init__(self, skip_token_check=False):
        # Trakt Configuration
        self.trakt_client_id = os.getenv('TRAKT_CLIENT_ID')
        self.trakt_client_secret = os.getenv('TRAKT_CLIENT_SECRET')
        self.trakt_redirect_uri = 'urn:ietf:wg:oauth:2.0:oob'
        
        # Radarr Configuration
        self.radarr_url = os.getenv('RADARR_URL', 'http://radarr:7878')
        self.radarr_api_key = os.getenv('RADARR_API_KEY')
        self.radarr_root_folder = os.getenv('RADARR_ROOT_FOLDER', '/media/movies')
        self.radarr_quality_profile = os.getenv('RADARR_QUALITY_PROFILE', 'Any')

        # Sonarr Configuration
        self.sonarr_url = os.getenv('SONARR_URL', 'http://sonarr:8989')
        self.sonarr_api_key = os.getenv('SONARR_API_KEY')
        self.sonarr_root_folder = os.getenv('SONARR_ROOT_FOLDER', '/media/tv')
        self.sonarr_quality_profile = os.getenv('SONARR_QUALITY_PROFILE', 'Any')
        
        # Sync Configuration
        self.poll_interval = int(os.getenv('POLL_INTERVAL', '30'))
        self.tokens = None
        
        # Validate configuration
        self._validate_config()
        
        # Skip token check if we're just doing setup
        if not skip_token_check:
            # Check if we need to authenticate
            if not self.load_tokens():
                logger.error("No Trakt tokens found. Please authenticate first!")
                logger.error("Run: docker-compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup")
                raise ValueError("Trakt authentication required")
            
            # Get quality profile IDs
            self.radarr_quality_profile_id = self._get_radarr_quality_profile_id()
            self.sonarr_quality_profile_id = self._get_sonarr_quality_profile_id()
            
            logger.info("Trakt Watchlist Sync Service initialized")
            logger.info(f"Poll interval: {self.poll_interval} seconds")
    
    def load_tokens(self):
        """Load access tokens from file"""
        try:
            if os.path.exists(TOKEN_FILE):
                with open(TOKEN_FILE, 'r') as f:
                    self.tokens = json.load(f)
                    logger.info("Loaded Trakt tokens successfully")
                    return True
        except Exception as e:
            logger.error(f"Error loading tokens: {e}")
        return False
    
    def save_tokens(self, tokens):
        """Save access tokens to file"""
        try:
            os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
            with open(TOKEN_FILE, 'w') as f:
                json.dump(tokens, f, indent=2)
            self.tokens = tokens
            logger.info("Tokens saved successfully")
        except Exception as e:
            logger.error(f"Error saving tokens: {e}")
    
    def refresh_access_token(self):
        """Refresh expired access token"""
        url = 'https://api.trakt.tv/oauth/token'
        data = {
            'refresh_token': self.tokens.get('refresh_token'),
            'client_id': self.trakt_client_id,
            'client_secret': self.trakt_client_secret,
            'redirect_uri': self.trakt_redirect_uri,
            'grant_type': 'refresh_token'
        }
        headers = {'Content-Type': 'application/json'}
        
        try:
            response = requests.post(url, json=data, headers=headers)
            if response.status_code == 200:
                new_tokens = response.json()
                new_tokens['created_at'] = int(time.time())
                self.save_tokens(new_tokens)
                logger.info("Access token refreshed successfully")
                return True
            else:
                logger.error(f"Token refresh failed: {response.status_code} {response.text}")
                return False
        except Exception as e:
            logger.error(f"Error refreshing token: {e}")
            return False
    
    def get_valid_token(self):
        """Get a valid access token, refreshing if necessary"""
        if not self.tokens:
            return None
        
        # Check if token is expired (with 10 minute buffer)
        expires_at = self.tokens.get('created_at', 0) + self.tokens.get('expires_in', 0) - 600
        if time.time() > expires_at:
            logger.info("Token expired, refreshing...")
            if not self.refresh_access_token():
                logger.error("Token refresh failed. Please re-authenticate.")
                return None
        
        return self.tokens.get('access_token')
    
    def get_device_code(self):
        """Get device code for authentication"""
        url = 'https://api.trakt.tv/oauth/device/code'
        data = {'client_id': self.trakt_client_id}
        headers = {'Content-Type': 'application/json'}
        
        try:
            response = requests.post(url, json=data, headers=headers)
            return response.json()
        except Exception as e:
            logger.error(f"Error getting device code: {e}")
            return None
    
    def get_access_token_from_device(self, device_code, interval):
        """Poll for access token"""
        url = 'https://api.trakt.tv/oauth/device/token'
        data = {
            'code': device_code,
            'client_id': self.trakt_client_id,
            'client_secret': self.trakt_client_secret
        }
        headers = {'Content-Type': 'application/json'}
        
        max_attempts = 60
        attempts = 0
        
        while attempts < max_attempts:
            try:
                response = requests.post(url, json=data, headers=headers)
                
                if not response.text:
                    time.sleep(interval)
                    attempts += 1
                    continue
                
                try:
                    result = response.json()
                except json.JSONDecodeError:
                    time.sleep(interval)
                    attempts += 1
                    continue
                
                if response.status_code == 200:
                    logger.info("Authentication successful!")
                    return result
                elif result.get('error') == 'authorization_pending':
                    time.sleep(interval)
                    attempts += 1
                elif result.get('error') == 'slow_down':
                    time.sleep(interval + 1)
                    attempts += 1
                else:
                    logger.error(f"Token error: {result}")
                    return None
            except Exception as e:
                logger.error(f"Error polling for token: {e}")
                time.sleep(interval)
                attempts += 1
        
        logger.error("Token polling timeout")
        return None
    
    def setup_authentication(self):
        """Setup Trakt authentication"""
        logger.info("Setting up Trakt authentication...")
        
        device_response = self.get_device_code()
        if not device_response:
            logger.error("Failed to get device code")
            return False
        
        print(f"\nPlease go to: {device_response['verification_url']}")
        print(f"And enter this code: {device_response['user_code']}")
        print("Waiting for authentication...")
        
        time.sleep(5)
        
        tokens = self.get_access_token_from_device(device_response['device_code'], device_response['interval'])
        if tokens:
            tokens['created_at'] = int(time.time())
            self.save_tokens(tokens)
            logger.info("Authentication successful!")
            return True
        else:
            logger.error("Authentication failed")
            return False
    
    def _validate_config(self):
        """Validate required configuration"""
        required = {
            'TRAKT_CLIENT_ID': self.trakt_client_id,
            'TRAKT_CLIENT_SECRET': self.trakt_client_secret,
            'RADARR_API_KEY': self.radarr_api_key,
            'SONARR_API_KEY': self.sonarr_api_key,
        }
        
        missing = [k for k, v in required.items() if not v]
        if missing:
            raise ValueError(f"Missing required configuration: {', '.join(missing)}")
    
    def _get_radarr_quality_profile_id(self) -> int:
        """Get Radarr quality profile ID"""
        try:
            response = requests.get(
                f"{self.radarr_url}/api/v3/qualityprofile",
                headers={'X-Api-Key': self.radarr_api_key}
            )
            response.raise_for_status()
            profiles = response.json()
            
            for profile in profiles:
                if profile['name'].lower() == self.radarr_quality_profile.lower():
                    logger.info(f"Found Radarr quality profile '{profile['name']}' with ID {profile['id']}")
                    return profile['id']
            
            # Fallback to first profile
            logger.warning(f"Quality profile '{self.radarr_quality_profile}' not found, using first available")
            return profiles[0]['id']
        except Exception as e:
            logger.error(f"Error getting Radarr quality profiles: {e}")
            return 1  # Default fallback
    
    def _get_sonarr_quality_profile_id(self) -> int:
        """Get Sonarr quality profile ID"""
        try:
            response = requests.get(
                f"{self.sonarr_url}/api/v3/qualityprofile",
                headers={'X-Api-Key': self.sonarr_api_key}
            )
            response.raise_for_status()
            profiles = response.json()
            
            for profile in profiles:
                if profile['name'].lower() == self.sonarr_quality_profile.lower():
                    logger.info(f"Found Sonarr quality profile '{profile['name']}' with ID {profile['id']}")
                    return profile['id']
            
            # Fallback to first profile
            logger.warning(f"Quality profile '{self.sonarr_quality_profile}' not found, using first available")
            return profiles[0]['id']
        except Exception as e:
            logger.error(f"Error getting Sonarr quality profiles: {e}")
            return 1  # Default fallback

    def _get_radarr_root_folder(self) -> str:
        """Get the first configured root folder directly from Radarr's API.
        Falls back to the env var value if the API call fails."""
        try:
            response = requests.get(
                f"{self.radarr_url}/api/v3/rootfolder",
                headers={'X-Api-Key': self.radarr_api_key}
            )
            response.raise_for_status()
            folders = response.json()
            if folders:
                path = folders[0]['path']
                logger.info(f"Using Radarr root folder from API: {path}")
                return path
        except Exception as e:
            logger.error(f"Error fetching Radarr root folders, falling back to env var: {e}")
        return self.radarr_root_folder

    def _get_sonarr_root_folder(self) -> str:
        """Get the first configured root folder directly from Sonarr's API.
        Falls back to the env var value if the API call fails."""
        try:
            response = requests.get(
                f"{self.sonarr_url}/api/v3/rootfolder",
                headers={'X-Api-Key': self.sonarr_api_key}
            )
            response.raise_for_status()
            folders = response.json()
            if folders:
                path = folders[0]['path']
                logger.info(f"Using Sonarr root folder from API: {path}")
                return path
        except Exception as e:
            logger.error(f"Error fetching Sonarr root folders, falling back to env var: {e}")
        return self.sonarr_root_folder

    def add_movie_to_radarr(self, movie_data: Dict) -> bool:
        """Add movie to Radarr"""
        try:
            movie = movie_data.get('movie', {})
            title = movie.get('title')
            year = movie.get('year')
            tmdb_id = movie.get('ids', {}).get('tmdb')
            
            if not tmdb_id:
                logger.warning(f"No TMDB ID for movie: {title}")
                return False
            
            # Lookup movie in Radarr to get full details
            lookup_response = requests.get(
                f"{self.radarr_url}/api/v3/movie/lookup/tmdb",
                params={'tmdbId': tmdb_id},
                headers={'X-Api-Key': self.radarr_api_key}
            )
            lookup_response.raise_for_status()
            radarr_movie = lookup_response.json()
            
            if not radarr_movie:
                logger.warning(f"Movie not found in Radarr lookup: {title} ({year})")
                return False
            
            # Resolve the root folder Radarr actually knows about
            root_folder = self._get_radarr_root_folder()

            # Prepare payload
            payload = {
                'title': radarr_movie.get('title'),
                'year': radarr_movie.get('year'),
                'qualityProfileId': self.radarr_quality_profile_id,
                'tmdbId': tmdb_id,
                'images': radarr_movie.get('images', []),
                'titleSlug': radarr_movie.get('titleSlug'),
                'rootFolderPath': root_folder,
                'monitored': True,  # MUST be monitored for automatic download
                'addOptions': {
                    'searchForMovie': True  # Search immediately
                }
            }
            
            # Add movie
            add_response = requests.post(
                f"{self.radarr_url}/api/v3/movie",
                json=payload,
                headers={'X-Api-Key': self.radarr_api_key}
            )
            add_response.raise_for_status()
            
            logger.info(f"✅ Added movie to Radarr: {title} ({year})")
            return True
            
        except Exception as e:
            body = getattr(getattr(e, 'response', None), 'text', 'no body')
            logger.error(f"Error adding movie to Radarr: {e} | Response body: {body}")
            return False
    
    def add_show_to_sonarr(self, show_data: Dict) -> bool:
        """Add show to Sonarr - Download full Season 1 if available, else first 3 episodes"""
        try:
            show = show_data.get('show', {})
            title = show.get('title')
            tvdb_id = show.get('ids', {}).get('tvdb')
            
            if not tvdb_id:
                logger.warning(f"No TVDB ID for show: {title}")
                return False
            
            # Lookup show in Sonarr to get full details
            lookup_response = requests.get(
                f"{self.sonarr_url}/api/v3/series/lookup",
                params={'term': f'tvdb:{tvdb_id}'},
                headers={'X-Api-Key': self.sonarr_api_key}
            )
            lookup_response.raise_for_status()
            lookup_results = lookup_response.json()
            
            if not lookup_results:
                logger.warning(f"Show not found in Sonarr lookup: {title}")
                return False
            
            sonarr_show = lookup_results[0]
            
            # Check if Season 1 exists and has episodes
            seasons = sonarr_show.get('seasons', [])
            season_1 = next((s for s in seasons if s.get('seasonNumber') == 1), None)
            
            if not season_1:
                logger.warning(f"Season 1 not found for show: {title}")
                return False
            
            # Check if Season 1 is marked as available (ended)
            show_status = sonarr_show.get('status', '').lower()
            season_1_episode_count = season_1.get('statistics', {}).get('episodeCount', 0)
            
            # Determine strategy: download full season if it has episodes
            if season_1_episode_count > 0:
                logger.info(f"Season 1 has {season_1_episode_count} episodes - will download full season")
                download_full_season = True
            else:
                logger.info(f"Season 1 episode count unavailable - will download first 3 episodes only")
                download_full_season = False
            
            # Configure seasons - Monitor Season 1 ALWAYS for downloads to work
            for season in seasons:
                if season.get('seasonNumber') == 1:
                    season['monitored'] = True  # MUST be monitored
                else:
                    season['monitored'] = False  # Don't monitor other seasons

            # Resolve the root folder Sonarr actually knows about
            root_folder = self._get_sonarr_root_folder()

            # Prepare payload
            payload = {
                'title': sonarr_show.get('title'),
                'qualityProfileId': self.sonarr_quality_profile_id,
                'tvdbId': tvdb_id,
                'titleSlug': sonarr_show.get('titleSlug'),
                'images': sonarr_show.get('images', []),
                'seasons': seasons,
                'rootFolderPath': root_folder,
                'monitored': True,  # Series must be monitored
                'seasonFolder': True,
                'addOptions': {
                    'searchForMissingEpisodes': True  # ALWAYS trigger search immediately
                }
            }
            
            # Add show
            add_response = requests.post(
                f"{self.sonarr_url}/api/v3/series",
                json=payload,
                headers={'X-Api-Key': self.sonarr_api_key}
            )
            add_response.raise_for_status()
            result = add_response.json()
            
            # Get series ID
            series_id = result.get('id')
            
            if series_id and not download_full_season:
                logger.info(f"Triggering additional episode search for {title}")
                self._search_first_episodes(series_id, 1, 3)
            
            logger.info(f"✅ Added show to Sonarr: {title}")
            return True
            
        except Exception as e:
            logger.error(f"Error adding show to Sonarr: {e}")
            return False
    
    def _search_full_season(self, series_id: int, season_number: int):
        """Search for entire season"""
        try:
            payload = {
                'name': 'SeasonSearch',
                'seriesId': series_id,
                'seasonNumber': season_number
            }
            requests.post(
                f"{self.sonarr_url}/api/v3/command",
                json=payload,
                headers={'X-Api-Key': self.sonarr_api_key}
            )
            logger.info(f"Triggered full season {season_number} search")
        except Exception as e:
            logger.error(f"Error searching for season: {e}")
    
    def _search_first_episodes(self, series_id: int, season_number: int, episode_count: int):
        """Search for first N episodes of a season"""
        try:
            # Get all episodes for the series
            episodes_response = requests.get(
                f"{self.sonarr_url}/api/v3/episode",
                params={'seriesId': series_id},
                headers={'X-Api-Key': self.sonarr_api_key}
            )
            episodes_response.raise_for_status()
            all_episodes = episodes_response.json()
            
            # Filter for first N episodes of the season
            season_episodes = [
                ep for ep in all_episodes
                if ep.get('seasonNumber') == season_number
            ]
            season_episodes.sort(key=lambda x: x.get('episodeNumber', 0))
            
            # Get first N episodes
            first_episodes = season_episodes[:episode_count]
            episode_ids = [ep['id'] for ep in first_episodes]
            
            if episode_ids:
                # Monitor these episodes
                monitor_payload = {'episodeIds': episode_ids, 'monitored': True}
                requests.put(
                    f"{self.sonarr_url}/api/v3/episode/monitor",
                    json=monitor_payload,
                    headers={'X-Api-Key': self.sonarr_api_key}
                )
                
                # Trigger episode search
                requests.post(
                    f"{self.sonarr_url}/api/v3/command",
                    json={'name': 'EpisodeSearch', 'episodeIds': episode_ids},
                    headers={'X-Api-Key': self.sonarr_api_key}
                )
                logger.info(f"Triggered search for first {len(episode_ids)} episodes")
        except Exception as e:
            logger.error(f"Error searching for episodes: {e}")
    
    def process_watchlist(self):
        """Process entire Trakt watchlist"""
        watchlist = self.get_trakt_watchlist()
        
        if not watchlist:
            logger.info("Watchlist is empty or couldn't be fetched")
            return
        
        processed = {'movies': 0, 'shows': 0, 'skipped': 0}
        
        for item in watchlist:
            item_type = item.get('type')
            
            if item_type == 'movie':
                movie = item.get('movie', {})
                tmdb_id = movie.get('ids', {}).get('tmdb')
                title = movie.get('title')
                
                if tmdb_id and not self.movie_exists_in_radarr(tmdb_id):
                    if self.add_movie_to_radarr(item):
                        processed['movies'] += 1
                else:
                    logger.debug(f"Movie already exists in Radarr: {title}")
                    processed['skipped'] += 1
            
            elif item_type == 'show':
                show = item.get('show', {})
                tvdb_id = show.get('ids', {}).get('tvdb')
                title = show.get('title')
                
                if tvdb_id and not self.show_exists_in_sonarr(tvdb_id):
                    if self.add_show_to_sonarr(item):
                        processed['shows'] += 1
                else:
                    logger.debug(f"Show already exists in Sonarr: {title}")
                    processed['skipped'] += 1
    
    def get_trakt_watchlist(self) -> List[Dict]:
        """Fetch watchlist from Trakt"""
        try:
            access_token = self.get_valid_token()
            if not access_token:
                logger.error("No valid access token available")
                return []
            
            headers = {
                'Content-Type': 'application/json',
                'trakt-api-version': '2',
                'trakt-api-key': self.trakt_client_id,
                'Authorization': f'Bearer {access_token}'
            }
            
            # Get movies
            movies_response = requests.get(
                'https://api.trakt.tv/sync/watchlist/movies',
                headers=headers
            )
            movies_response.raise_for_status()
            movies = movies_response.json()
            
            # Get shows
            shows_response = requests.get(
                'https://api.trakt.tv/sync/watchlist/shows',
                headers=headers
            )
            shows_response.raise_for_status()
            shows = shows_response.json()
            return movies + shows
            
        except Exception as e:
            logger.error(f"Error fetching Trakt watchlist: {e}")
            return []
    
    def movie_exists_in_radarr(self, tmdb_id: int) -> bool:
        """Check if movie exists in Radarr"""
        try:
            response = requests.get(
                f"{self.radarr_url}/api/v3/movie",
                headers={'X-Api-Key': self.radarr_api_key}
            )
            response.raise_for_status()
            movies = response.json()
            
            return any(movie.get('tmdbId') == tmdb_id for movie in movies)
        except Exception as e:
            logger.error(f"Error checking Radarr for movie: {e}")
            return False
    
    def show_exists_in_sonarr(self, tvdb_id: int) -> bool:
        """Check if show exists in Sonarr"""
        try:
            response = requests.get(
                f"{self.sonarr_url}/api/v3/series",
                headers={'X-Api-Key': self.sonarr_api_key}
            )
            response.raise_for_status()
            series = response.json()
            
            return any(show.get('tvdbId') == tvdb_id for show in series)
        except Exception as e:
            logger.error(f"Error checking Sonarr for show: {e}")
            return False

    def run(self):
        """Main loop"""
        logger.info("Starting Trakt Watchlist Sync Service...")
        logger.info(f"Monitoring Trakt watchlist every {self.poll_interval} seconds")
        
        while True:
            try:
                self.process_watchlist()
                time.sleep(self.poll_interval)
            except KeyboardInterrupt:
                logger.info("Shutting down...")
                break
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                logger.info(f"Retrying in {self.poll_interval} seconds...")
                time.sleep(self.poll_interval)


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Trakt Watchlist to Radarr/Sonarr Sync')
    parser.add_argument('--setup', action='store_true', help='Setup Trakt authentication')
    
    args = parser.parse_args()
    
    try:
        # If setup mode, skip token check during initialization
        sync = TraktWatchlistSync(skip_token_check=args.setup)
        
        # Handle setup
        if args.setup:
            sync.setup_authentication()
        else:
            sync.run()
    except ValueError as e:
        logger.error(str(e))
        if "authentication required" in str(e).lower():
            logger.info("Run with --setup flag to authenticate: docker-compose run --rm trakt-watchlist-sync python /app/trakt-watchlist-sync.py --setup")