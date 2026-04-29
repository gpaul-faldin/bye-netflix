#!/usr/bin/env python3
"""
Trakt Watchlist Cleanup Service
Listens for Radarr/Sonarr delete events and removes items from Trakt watchlist

Webhook endpoints:
- POST /radarr - Handles movie deletions from Radarr
- POST /sonarr - Handles show deletions from Sonarr
"""

import os
import json
import time
import logging
import requests
from flask import Flask, request, jsonify

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Token management
TOKEN_FILE = '/config/trakt_tokens.json'

# Flask app
app = Flask(__name__)


class TraktWatchlistCleanup:
    def __init__(self):
        self.trakt_client_id = os.getenv('TRAKT_CLIENT_ID')
        self.trakt_client_secret = os.getenv('TRAKT_CLIENT_SECRET')
        self.trakt_redirect_uri = 'urn:ietf:wg:oauth:2.0:oob'
        self.tokens = None
        
        # Load tokens
        self.load_tokens()
    
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
                logger.error(f"Token refresh failed: {response.status_code}")
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
                logger.error("Token refresh failed")
                return None
        
        return self.tokens.get('access_token')
    
    def remove_from_watchlist(self, media_type, tmdb_id=None, tvdb_id=None, imdb_id=None, title=None):
        """Remove item from Trakt watchlist"""
        access_token = self.get_valid_token()
        if not access_token:
            logger.error("No valid access token available")
            return False
        
        headers = {
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': self.trakt_client_id,
            'Authorization': f'Bearer {access_token}'
        }
        
        # Build the item object
        if media_type == 'movie':
            item = {
                "movies": [{
                    "ids": {}
                }]
            }
            if tmdb_id:
                item["movies"][0]["ids"]["tmdb"] = tmdb_id
            if imdb_id:
                item["movies"][0]["ids"]["imdb"] = imdb_id
            if title:
                item["movies"][0]["title"] = title
        else:  # show
            item = {
                "shows": [{
                    "ids": {}
                }]
            }
            if tvdb_id:
                item["shows"][0]["ids"]["tvdb"] = tvdb_id
            if tmdb_id:
                item["shows"][0]["ids"]["tmdb"] = tmdb_id
            if imdb_id:
                item["shows"][0]["ids"]["imdb"] = imdb_id
            if title:
                item["shows"][0]["title"] = title
        
        try:
            logger.info(f"Removing {media_type} from Trakt watchlist: {title}")
            response = requests.post(
                'https://api.trakt.tv/sync/watchlist/remove',
                headers=headers,
                json=item
            )
            
            if response.status_code in [200, 201]:
                result = response.json()
                deleted = result.get('deleted', {})
                movies_deleted = deleted.get('movies', 0)
                shows_deleted = deleted.get('shows', 0)
                
                if movies_deleted > 0 or shows_deleted > 0:
                    logger.info(f"✅ Removed from Trakt watchlist: {title}")
                    return True
                else:
                    logger.info(f"ℹ️  Item not in watchlist: {title}")
                    return False
            else:
                logger.error(f"Failed to remove from Trakt: {response.status_code} {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Error removing from Trakt: {e}")
            return False


# Global instance
cleanup = TraktWatchlistCleanup()


@app.route('/radarr', methods=['POST'])
def radarr_webhook():
    """Handle Radarr webhook events"""
    try:
        data = request.json
        event_type = data.get('eventType')
        
        logger.info(f"Received Radarr event: {event_type}")
        
        if event_type == 'MovieDelete':
            movie = data.get('movie', {})
            delete_reason = data.get('deleteMessage', 'Unknown')
            
            title = movie.get('title')
            year = movie.get('year')
            tmdb_id = movie.get('tmdbId')
            imdb_id = movie.get('imdbId')
            
            logger.info(f"Movie deleted: {title} ({year}) - Reason: {delete_reason}")
            
            # Remove from Trakt watchlist
            cleanup.remove_from_watchlist(
                media_type='movie',
                tmdb_id=tmdb_id,
                imdb_id=imdb_id,
                title=title
            )
        
        return jsonify({'status': 'success'}), 200
        
    except Exception as e:
        logger.error(f"Error processing Radarr webhook: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/sonarr', methods=['POST'])
def sonarr_webhook():
    """Handle Sonarr webhook events"""
    try:
        data = request.json
        event_type = data.get('eventType')
        
        logger.info(f"Received Sonarr event: {event_type}")
        
        if event_type == 'SeriesDelete':
            series = data.get('series', {})
            delete_reason = data.get('deleteMessage', 'Unknown')
            
            title = series.get('title')
            tvdb_id = series.get('tvdbId')
            imdb_id = series.get('imdbId')
            
            logger.info(f"Series deleted: {title} - Reason: {delete_reason}")
            
            # Remove from Trakt watchlist
            cleanup.remove_from_watchlist(
                media_type='show',
                tvdb_id=tvdb_id,
                imdb_id=imdb_id,
                title=title
            )
        
        return jsonify({'status': 'success'}), 200
        
    except Exception as e:
        logger.error(f"Error processing Sonarr webhook: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'}), 200


if __name__ == '__main__':
    logger.info("Starting Trakt Watchlist Cleanup Service...")
    app.run(host='0.0.0.0', port=5000, debug=False)