#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Progressive Season Downloader for Plex + Sonarr + Tautulli

When a user watches an episode, this script will:
1. Check if at last available episode → Enable ALL seasons monitoring
2. Check if they're at the halfway point of the current season
3. If yes, download the COMPLETE next season (if it exists in Sonarr)
4. If next season doesn't exist, fall back to downloading next 2-3 episodes

Setup in Tautulli:
Triggers: Playback Start
Conditions: Media Type is episode
Arguments: -tvid {thetvdb_id} -sn {season_num} -en {episode_num}
"""

from __future__ import print_function
from __future__ import unicode_literals
import requests
import sys
import os
import argparse
import json

# ## CONFIGURATION - EDIT THESE SETTINGS ##
SONARR_APIKEY = ''  # Your Sonarr API key (Settings > General > Security)
SONARR_URL = 'http://sonarr:8989'   # Your Sonarr URL (e.g., http://192.168.1.100:8989)
EPISODE_BUFFER = 3                      # Number of episodes to download if full season not available
HALFWAY_THRESHOLD = 0.5                 # Download next season when 50% through current season (0.5 = 50%)
SET_WANTED = True                       # Mark episodes/seasons as wanted/monitored
AUTO_SEARCH = True                      # Automatically search for episodes/seasons
VERBOSE_LOGGING = True                  # Enable detailed logging for debugging

def log(message):
    """Print log message to stderr for Tautulli logging"""
    if VERBOSE_LOGGING:
        sys.stderr.write(f"[Progressive Downloader] {message}\n")

def get_headers(with_json=False):
    """Generate headers for Sonarr API requests"""
    headers = {'X-Api-Key': SONARR_APIKEY}
    if with_json:
        headers['Content-Type'] = 'application/json'
    return headers

def get_series_id(tvdbid):
    """Get Sonarr series ID from TVDB ID"""
    payload = {'tvdbId': tvdbid, 'includeSeasonImages': False}
    try:
        r = requests.get(SONARR_URL.rstrip('/') + '/api/v3/series', 
                        headers=get_headers(), params=payload)
        response = r.json()
        if response and len(response) > 0:
            log(f"Found series: {response[0].get('title', 'Unknown')} (ID: {response[0]['id']})")
            return response[0]['id']
        else:
            log(f"No series found for TVDB ID: {tvdbid}")
            return None
    except Exception as e:
        sys.stderr.write(f"Sonarr API 'get_series_id' request failed: {e}\n")
        return None

def get_episodes(series_id):
    """Get all episodes for a series from Sonarr"""
    payload = {'seriesId': series_id}
    try:
        r = requests.get(SONARR_URL.rstrip('/') + '/api/v3/episode', 
                        headers=get_headers(), params=payload)
        response = r.json()
        log(f"Retrieved {len(response)} episodes for series ID {series_id}")
        return response
    except Exception as e:
        sys.stderr.write(f"Sonarr API 'get_episodes' request failed: {e}\n")
        return []

def get_season_episodes(episodes, season_number):
    """Get all episodes for a specific season"""
    season_eps = [ep for ep in episodes if int(ep['seasonNumber']) == int(season_number)]
    log(f"Season {season_number} has {len(season_eps)} episodes")
    return season_eps

def is_season_available_in_sonarr(episodes, season_number):
    """Check if a season exists in Sonarr's database"""
    season_eps = get_season_episodes(episodes, season_number)
    if len(season_eps) > 0:
        # Check if season has aired (at least one episode has aired)
        aired_count = sum(1 for ep in season_eps if ep.get('hasFile', False) or ep.get('airDateUtc'))
        log(f"Season {season_number}: {len(season_eps)} total episodes, {aired_count} aired/available")
        return len(season_eps) > 0, season_eps
    return False, []

def is_at_season_halfway(episodes, season_number, episode_number):
    """Check if current viewing position is at or past halfway point of season"""
    season_eps = get_season_episodes(episodes, season_number)
    if len(season_eps) == 0:
        return False
    
    halfway_point = len(season_eps) * HALFWAY_THRESHOLD
    log(f"Season {season_number}: Episode {episode_number} of {len(season_eps)} (halfway at {halfway_point:.1f})")
    
    return episode_number >= halfway_point

def is_at_last_available_episode(episodes, season_number, episode_number):
    """Check if current episode is the last one available (has file)"""
    # Get all episodes sorted by season and episode number
    sorted_episodes = sorted(episodes, key=lambda x: (x.get('seasonNumber', 0), x.get('episodeNumber', 0)))
    
    # Find current episode index
    current_index = None
    for i, ep in enumerate(sorted_episodes):
        if (int(ep['seasonNumber']) == int(season_number) and 
            int(ep['episodeNumber']) == int(episode_number)):
            current_index = i
            break
    
    if current_index is None:
        return False
    
    # Check if there are any episodes after current that have files
    for ep in sorted_episodes[current_index + 1:]:
        if ep.get('hasFile', False):
            return False  # There are more episodes available
    
    # Check if there are any future episodes (not yet aired/available)
    has_future_episodes = False
    for ep in sorted_episodes[current_index + 1:]:
        if ep.get('airDateUtc'):  # Episode has an air date (exists in DB)
            has_future_episodes = True
            break
    
    log(f"At last available episode. Future episodes announced: {has_future_episodes}")
    return True

def get_next_episodes_buffer(episodes, season_number, episode_number):
    """Get the next N episodes as a buffer (fallback method)"""
    next_episodes = []
    found_current = False
    
    for episode in episodes:
        if found_current and not episode.get('hasFile', False):
            next_episodes.append(episode)
            if len(next_episodes) >= EPISODE_BUFFER:
                break
        
        if (int(episode['seasonNumber']) == int(season_number) and 
            int(episode['episodeNumber']) == int(episode_number)):
            found_current = True
    
    log(f"Episode buffer: Found {len(next_episodes)} next episodes to download")
    return next_episodes

def set_wanted(episode_id):
    """Mark an episode as wanted/monitored in Sonarr"""
    payload = {'episodeIds': [episode_id], 'monitored': True}
    try:
        r = requests.put(SONARR_URL.rstrip('/') + '/api/v3/episode/monitor', 
                        headers=get_headers(True), data=json.dumps(payload))
        return r.json()
    except Exception as e:
        sys.stderr.write(f"Sonarr API 'set_wanted' request failed: {e}\n")
        return None

def search_episode(episode_id):
    """Trigger a search for a specific episode in Sonarr"""
    payload = {'episodeIds': [episode_id], 'name': 'EpisodeSearch'}
    try:
        r = requests.post(SONARR_URL.rstrip('/') + '/api/v3/command', 
                         headers=get_headers(True), data=json.dumps(payload))
        return r.json()
    except Exception as e:
        sys.stderr.write(f"Sonarr API 'search_episode' request failed: {e}\n")
        return None

def get_series(series_id):
    """Get series details from Sonarr"""
    try:
        r = requests.get(SONARR_URL.rstrip('/') + '/api/v3/series/' + str(series_id), 
                        headers=get_headers())
        response = r.json()
        return response
    except Exception as e:
        sys.stderr.write(f"Sonarr API 'get_series' request failed: {e}\n")
        return None

def ensure_series_monitored(series_id):
    """Ensure the series itself is monitored"""
    series = get_series(series_id)
    if not series:
        log(f"Could not get series {series_id}")
        return False
    
    if series.get('monitored', False):
        log(f"Series already monitored")
        return True
    
    # Series is not monitored, let's monitor it
    log(f"Series not monitored, enabling monitoring...")
    series['monitored'] = True
    
    try:
        r = requests.put(SONARR_URL.rstrip('/') + '/api/v3/series/' + str(series_id),
                        headers=get_headers(True), json=series)
        log(f"Series monitoring enabled")
        return True
    except Exception as e:
        sys.stderr.write(f"Failed to monitor series: {e}\n")
        return False

def monitor_season(series_id, season_number):
    """Monitor an entire season at the series level"""
    series = get_series(series_id)
    if not series:
        log(f"Could not get series {series_id}")
        return False
    
    log(f"Monitoring season {season_number} at series level...")
    
    # Ensure series is monitored
    series['monitored'] = True
    
    # Find and monitor the specific season
    season_found = False
    for season in series.get('seasons', []):
        if int(season['seasonNumber']) == int(season_number):
            season['monitored'] = True
            season_found = True
            log(f"Found season {season_number}, setting monitored=True")
            break
    
    if not season_found:
        log(f"Season {season_number} not found in series data")
        return False
    
    try:
        r = requests.put(SONARR_URL.rstrip('/') + '/api/v3/series/' + str(series_id),
                        headers=get_headers(True), json=series)
        log(f"✅ Season {season_number} now monitored at series level")
        return True
    except Exception as e:
        sys.stderr.write(f"Sonarr API 'monitor_season' request failed: {e}\n")
        return False

def monitor_all_seasons(series_id):
    """Enable monitoring for ALL seasons of a series"""
    series = get_series(series_id)
    if not series:
        log(f"Could not get series {series_id}")
        return False
    
    log(f"Enabling monitoring for ALL seasons of {series.get('title', 'Unknown')}")
    
    # Ensure series is monitored
    series['monitored'] = True
    
    # Monitor all seasons
    for season in series.get('seasons', []):
        season['monitored'] = True
    
    try:
        r = requests.put(SONARR_URL.rstrip('/') + '/api/v3/series/' + str(series_id),
                        headers=get_headers(True), json=series)
        log(f"✅ ALL seasons now monitored - Sonarr will handle future episodes automatically")
        return True
    except Exception as e:
        sys.stderr.write(f"Failed to monitor all seasons: {e}\n")
        return False

def search_season(series_id, season_number):
    """Trigger a search for an entire season in Sonarr"""
    payload = {
        'name': 'SeasonSearch',
        'seriesId': series_id,
        'seasonNumber': season_number
    }
    try:
        r = requests.post(SONARR_URL.rstrip('/') + '/api/v3/command',
                         headers=get_headers(True), data=json.dumps(payload))
        log(f"Triggered season search for season {season_number}")
        return r.json()
    except Exception as e:
        sys.stderr.write(f"Sonarr API 'search_season' request failed: {e}\n")
        return None

def download_full_season(series_id, episodes, season_number):
    """Download all episodes of a season"""
    season_episodes = get_season_episodes(episodes, season_number)
    
    if len(season_episodes) == 0:
        log(f"No episodes found for season {season_number}")
        return False
    
    log(f"Downloading full season {season_number} ({len(season_episodes)} episodes)")
    
    # CRITICAL: Ensure series itself is monitored
    if SET_WANTED:
        ensure_series_monitored(series_id)
        
        # Monitor the ENTIRE season at series level (not individual episodes)
        log(f"Setting season {season_number} as monitored at series level...")
        monitor_season(series_id, season_number)
    
    # Trigger season search (more efficient than individual episode searches)
    if AUTO_SEARCH:
        search_season(series_id, season_number)
    
    return True

def download_episode_buffer(episodes_to_download):
    """Download a buffer of individual episodes"""
    log(f"Downloading {len(episodes_to_download)} episodes as buffer")
    
    for episode in episodes_to_download:
        episode_id = int(episode['id'])
        season = episode['seasonNumber']
        episode_num = episode['episodeNumber']
        
        if not episode.get('hasFile', False):
            log(f"Queueing S{season:02d}E{episode_num:02d}")
            
            if SET_WANTED:
                set_wanted(episode_id)
            
            if AUTO_SEARCH:
                search_episode(episode_id)

def process_viewing_progress(series_id, season_number, episode_number):
    """Main logic to determine what to download based on viewing progress"""
    log(f"Processing: Series ID {series_id}, S{season_number:02d}E{episode_number:02d}")
    
    # Get all episodes for the series
    episodes = get_episodes(series_id)
    if not episodes:
        log("No episodes found in Sonarr")
        return
    
    # FIRST: Check if we're at the last available episode
    if is_at_last_available_episode(episodes, season_number, episode_number):
        log(f"🎯 Reached last available episode! Enabling ALL seasons monitoring...")
        monitor_all_seasons(series_id)
        log("✅ Sonarr will now automatically download future episodes when available")
        return  # Exit - Sonarr takes over from here
    
    # SECOND: Continue with progressive download logic
    # Check if next season exists first
    next_season = season_number + 1
    next_season_exists, next_season_eps = is_season_available_in_sonarr(episodes, next_season)
    
    # Check if we're at halfway point of current season
    at_halfway = is_at_season_halfway(episodes, season_number, episode_number)
    
    if at_halfway:
        log(f"At halfway point of season {season_number}!")
        
        if next_season_exists:
            log(f"Next season {next_season} found! Downloading full season...")
            download_full_season(series_id, episodes, next_season)
        else:
            log(f"Season {next_season} not available yet, using episode buffer")
            next_episodes = get_next_episodes_buffer(episodes, season_number, episode_number)
            if next_episodes:
                download_episode_buffer(next_episodes)
            else:
                log("No next episodes available to download")
    else:
        # Not at halfway yet
        if next_season_exists:
            log(f"Not at halfway point yet. Next season {next_season} exists, waiting to download full season at halfway point.")
            log("Skipping episode buffer - will download complete season later")
        else:
            log(f"Not at halfway point yet, and season {next_season} doesn't exist. Using episode buffer")
            next_episodes = get_next_episodes_buffer(episodes, season_number, episode_number)
            if next_episodes:
                download_episode_buffer(next_episodes)
            else:
                log("No next episodes available to download")

if __name__ == '__main__':
    # Parse arguments from Tautulli
    parser = argparse.ArgumentParser(description='Progressive Season Downloader')
    parser.add_argument('-tvid', '--series_id', action='store', default='',
                       help='The TVDB series ID')
    parser.add_argument('-sn', '--season_number', action='store', default='',
                       help='The season number')
    parser.add_argument('-en', '--episode_number', action='store', default='',
                       help='The episode number')
    
    args = parser.parse_args()
    
    # Validate arguments
    if not args.series_id:
        sys.stderr.write("Error: No TVDB ID provided\n")
        sys.exit(1)
    
    if not args.season_number or not args.episode_number:
        sys.stderr.write("Error: Season and episode numbers required\n")
        sys.exit(1)
    
    try:
        # Get Sonarr series ID from TVDB ID
        sonarr_series_id = get_series_id(args.series_id)
        
        if not sonarr_series_id:
            sys.stderr.write(f"Could not find series with TVDB ID: {args.series_id}\n")
            sys.exit(1)
        
        # Process the viewing progress and trigger downloads
        process_viewing_progress(
            sonarr_series_id,
            int(args.season_number),
            int(args.episode_number)
        )
        
        log("Processing complete!")
        
    except Exception as e:
        sys.stderr.write(f"Error processing request: {e}\n")
        sys.exit(1)