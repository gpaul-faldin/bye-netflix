#!/usr/bin/env python3
"""
Torrent Racing Supervisor - Per-Filter Slot Management
- Monitors Deluge for torrents meeting removal criteria (ratio > X OR time > X)
- Removes qualifying torrents
- Manages autobrr filters individually based on their specific slot limits
- Each filter has its own max slots and is managed independently
"""

import os
import time
import logging
import json
from datetime import datetime
from deluge_client import DelugeRPCClient
import requests

# Configuration from environment variables
RATIO_THRESHOLD = float(os.getenv('RATIO_THRESHOLD', '2.0'))
MIN_RATIO_FOR_TIME_REMOVAL = float(os.getenv('MIN_RATIO_FOR_TIME_REMOVAL', '1.0'))
TIME_THRESHOLD_DAYS = int(os.getenv('TIME_THRESHOLD_DAYS', '3'))
TIME_THRESHOLD = TIME_THRESHOLD_DAYS * 24 * 3600  # Convert to seconds
MIN_UPLOAD_SPEED_KBS = float(os.getenv('MIN_UPLOAD_SPEED_KBS', '100'))  # Keep torrents uploading above this speed

DELUGE_HOST = os.getenv('DELUGE_HOST', 'gluetun')
DELUGE_PORT = int(os.getenv('DELUGE_PORT', '58846'))
DELUGE_USER = os.getenv('DELUGE_USER', 'admin')
DELUGE_PASSWORD = os.getenv('DELUGE_PASSWORD', 'deluge')

AUTOBRR_URL = os.getenv('AUTOBRR_URL', 'http://autobrr:7474')
AUTOBRR_API_KEY = os.getenv('AUTOBRR_API_KEY', '')
RESPECT_MANUAL_DISABLE = os.getenv('RESPECT_MANUAL_DISABLE', 'true').lower() == 'true'

CHECK_INTERVAL = int(os.getenv('CHECK_INTERVAL', '60'))  # seconds

# Per-filter configuration: label -> (max_slots, filter_name)
# This maps Deluge labels to their slot limits and autobrr filter names
FILTER_CONFIG = {
    'autobrr-frmovie': {'max_slots': 5, 'filter_name': 'French Movies'},
    'autobrr-frtv': {'max_slots': 5, 'filter_name': 'French TV Shows'},
    'autobrr-intl-movie': {'max_slots': 5, 'filter_name': 'International Movies'},
    'autobrr-intl-tv': {'max_slots': 5, 'filter_name': 'International TV Shows'},
    'autobrr-adult': {'max_slots': 3, 'filter_name': 'Adult Content'},
}

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class RacingSupervisor:
    def __init__(self):
        self.deluge_client = None
        self.autobrr_filters = {}  # Cache of filter_name -> filter_id
        self.manually_disabled = set()  # Track filters manually disabled by user
        self.filters_we_enabled = set()  # Track filters we've successfully enabled
        
    def connect_deluge(self):
        """Connect to Deluge daemon"""
        try:
            self.deluge_client = DelugeRPCClient(
                DELUGE_HOST, 
                DELUGE_PORT, 
                DELUGE_USER, 
                DELUGE_PASSWORD
            )
            self.deluge_client.connect()
            logger.info(f"Connected to Deluge at {DELUGE_HOST}:{DELUGE_PORT}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Deluge: {e}")
            return False
    
    def get_torrents_by_label(self):
        """Get torrents grouped by their label"""
        try:
            # Method 1: Try getting session state first (more reliable)
            torrent_ids = self.deluge_client.call('core.get_session_state')
            
            if not torrent_ids:
                logger.warning("No torrents found in session state")
                return {}
            
            logger.info(f"Found {len(torrent_ids)} total torrents")
            
            # Get detailed status for each torrent
            torrents = {}
            for i, tid in enumerate(torrent_ids):
                try:
                    status = self.deluge_client.call(
                        'core.get_torrent_status',
                        tid,
                        ['name', 'ratio', 'seeding_time', 'state', 'label', 'upload_payload_rate']
                    )
                    if status:
                        torrents[tid] = status
                        # Debug first torrent to see what we're getting
                        if i == 0 and not hasattr(self, '_logged_first_torrent'):
                            logger.info(f"DEBUG - First torrent data: {status}")
                            self._logged_first_torrent = True
                except Exception as e:
                    logger.debug(f"Failed to get status for torrent {tid}: {e}")
            
            # Track all labels and states we see for debugging
            all_labels_seen = set()
            state_counts = {}
            
            # Group torrents by label
            torrents_by_label = {}
            for torrent_id, info in torrents.items():
                # Deluge returns bytes for keys, handle both bytes and strings
                state = info.get(b'state') or info.get('state')
                if isinstance(state, bytes):
                    state = state.decode('utf-8')
                
                label = info.get(b'label') or info.get('label', b'')
                if isinstance(label, bytes):
                    label = label.decode('utf-8')
                
                name = info.get(b'name') or info.get('name', b'Unknown')
                if isinstance(name, bytes):
                    name = name.decode('utf-8', errors='ignore')
                
                ratio = info.get(b'ratio') or info.get('ratio', 0)
                seeding_time = info.get(b'seeding_time') or info.get('seeding_time', 0)
                
                # Track all labels and states
                if label:
                    all_labels_seen.add(label)
                if state:
                    state_counts[state] = state_counts.get(state, 0) + 1
                
                # Log first few torrents on first run
                if not hasattr(self, '_logged_torrents'):
                    state_str = str(state) if state else 'None'
                    label_str = label if label else '(none)'
                    logger.info(f"  Torrent: {name[:40]:<40} | State: {state_str:<12} | Label: {label_str}")
                
                # Only count seeding torrents
                if state != 'Seeding':
                    continue
                
                # Only track configured labels
                if label not in FILTER_CONFIG:
                    if label and not hasattr(self, '_logged_unmatched'):
                        logger.warning(f"Torrent has unmatched label '{label}' - not in FILTER_CONFIG")
                    continue
                
                if label not in torrents_by_label:
                    torrents_by_label[label] = {}
                
                torrents_by_label[label][torrent_id] = info
            
            # Log summary on first run
            if not hasattr(self, '_logged_torrents'):
                logger.info(f"Total torrents: {len(torrents)}")
                logger.info(f"States: {state_counts}")
                logger.info(f"Labels found: {sorted(all_labels_seen) if all_labels_seen else '(none)'}")
                logger.info(f"Seeding torrents with racing labels: {sum(len(t) for t in torrents_by_label.values())}")
                self._logged_torrents = True
                self._logged_unmatched = True
            
            return torrents_by_label
        except Exception as e:
            logger.error(f"Failed to get torrents: {e}")
            import traceback
            logger.error(traceback.format_exc())
            return {}
    
    def remove_eligible_torrents(self, torrents_by_label):
        """Remove torrents that meet ratio OR time criteria, grouped by label"""
        removed_by_label = {}
        
        for label, torrents in torrents_by_label.items():
            removed_by_label[label] = []
            
            for torrent_id, info in torrents.items():
                ratio = info.get(b'ratio') or info.get('ratio', 0)
                seeding_time = info.get(b'seeding_time') or info.get('seeding_time', 0)
                name = info.get(b'name') or info.get('name', b'Unknown')
                upload_rate = info.get(b'upload_payload_rate') or info.get('upload_payload_rate', 0)
                
                # Decode bytes to string if needed
                if isinstance(name, bytes):
                    name = name.decode('utf-8', errors='ignore')
                
                should_remove = False
                reason = ""
                
                # Check if torrent is still actively uploading
                upload_speed_kbs = upload_rate / 1024  # Convert to KB/s
                is_hot = upload_speed_kbs >= MIN_UPLOAD_SPEED_KBS  # Uploading fast enough to keep
                
                if ratio >= RATIO_THRESHOLD:
                    if is_hot:
                        # Still uploading fast - keep surfing the wave!
                        hours = seeding_time / 3600
                        logger.info(f"[{label}] 🌊 Surfing: {name[:50]} (ratio {ratio:.2f}, uploading {upload_speed_kbs:.0f} KB/s)")
                        should_remove = False
                    else:
                        should_remove = True
                        reason = f"ratio {ratio:.2f} >= {RATIO_THRESHOLD}"
                elif seeding_time >= TIME_THRESHOLD and ratio >= MIN_RATIO_FOR_TIME_REMOVAL:
                    should_remove = True
                    hours = seeding_time / 3600
                    reason = f"time {hours:.1f}h >= {TIME_THRESHOLD_DAYS * 24}h AND ratio {ratio:.2f} >= {MIN_RATIO_FOR_TIME_REMOVAL}"
                elif seeding_time >= TIME_THRESHOLD and ratio < MIN_RATIO_FOR_TIME_REMOVAL:
                    # Dead torrent - log but keep seeding to try to recover ratio
                    hours = seeding_time / 3600
                    logger.warning(f"[{label}] Dead torrent: {name[:50]} (time {hours:.1f}h, ratio only {ratio:.2f}) - keeping to recover ratio")
                
                if should_remove:
                    try:
                        self.deluge_client.call('core.remove_torrent', torrent_id, True)
                        logger.info(f"[{label}] Removed: {name[:50]} ({reason})")
                        removed_by_label[label].append(name)
                    except Exception as e:
                        logger.error(f"Failed to remove torrent {name[:50]}: {e}")
        
        return removed_by_label
    
    def get_autobrr_filters(self):
        """Get filters from autobrr and cache the mapping"""
        if not AUTOBRR_API_KEY:
            logger.warning("No AUTOBRR_API_KEY set, skipping autobrr management")
            return
        
        try:
            headers = {"X-API-Token": AUTOBRR_API_KEY}
            response = requests.get(f"{AUTOBRR_URL}/api/filters", headers=headers, timeout=5)
            response.raise_for_status()
            
            filters = response.json()
            
            # Build mapping of filter_name -> filter object
            self.autobrr_filters = {}
            for f in filters:
                filter_name = f.get('name', '')
                # Match filter names from FILTER_CONFIG
                for label, config in FILTER_CONFIG.items():
                    if config['filter_name'] == filter_name:
                        self.autobrr_filters[filter_name] = f
                        break
            
            logger.info(f"Found {len(self.autobrr_filters)} matching autobrr filters")
        except Exception as e:
            logger.error(f"Failed to get autobrr filters: {e}")
    
    def toggle_autobrr_filter(self, filter_name, enable):
        """Enable/disable a specific autobrr filter"""
        if not AUTOBRR_API_KEY or filter_name not in self.autobrr_filters:
            return
        
        filter_obj = self.autobrr_filters[filter_name]
        filter_id = filter_obj.get('id')
        current_status = filter_obj.get('enabled', False)
        
        # Detect manual disables ONLY if:
        # 1. We want to enable
        # 2. Filter is currently disabled
        # 3. We previously enabled this filter (so the disable must be manual)
        if RESPECT_MANUAL_DISABLE and enable and not current_status and filter_name in self.filters_we_enabled:
            if filter_name not in self.manually_disabled:
                logger.info(f"Filter '{filter_name}' was enabled by supervisor but is now disabled - appears to be manually disabled")
                self.manually_disabled.add(filter_name)
            else:
                logger.debug(f"Filter '{filter_name}' is manually disabled - skipping auto-enable")
            return
        
        # Only update if status needs to change
        if current_status != enable:
            try:
                headers = {"X-API-Token": AUTOBRR_API_KEY}
                response = requests.patch(
                    f"{AUTOBRR_URL}/api/filters/{filter_id}",
                    headers=headers,
                    json={"enabled": enable},
                    timeout=5
                )
                response.raise_for_status()
                
                # Update cache
                self.autobrr_filters[filter_name]['enabled'] = enable
                
                # Track that we enabled this filter
                if enable:
                    self.filters_we_enabled.add(filter_name)
                    # Clear manual disable flag if we're successfully enabling it
                    if filter_name in self.manually_disabled:
                        logger.debug(f"Clearing manual disable flag for '{filter_name}' (re-enabled)")
                        self.manually_disabled.discard(filter_name)
                else:
                    # Clear manual disable flag when we disable programmatically
                    if filter_name in self.manually_disabled:
                        logger.debug(f"Clearing manual disable flag for '{filter_name}' (supervisor disabled)")
                        self.manually_disabled.discard(filter_name)
                
                status = "enabled" if enable else "disabled"
                logger.info(f"Filter '{filter_name}' {status}")
            except Exception as e:
                logger.error(f"Failed to toggle filter '{filter_name}': {e}")
    
    def manage_filter_slots(self, torrents_by_label, removed_by_label):
        """Manage each filter's status based on its slot usage"""
        
        # Refresh filter state from autobrr to catch manual changes
        self.get_autobrr_filters()
        
        for label, config in FILTER_CONFIG.items():
            max_slots = config['max_slots']
            filter_name = config['filter_name']
            
            # Count active torrents for this label
            active_count = len(torrents_by_label.get(label, {}))
            removed_count = len(removed_by_label.get(label, []))
            
            # After removal
            current_count = active_count - removed_count
            available_slots = max_slots - current_count
            
            # Decide filter status
            if current_count >= max_slots:
                # At capacity, disable filter
                logger.info(f"[{label}] At capacity ({current_count}/{max_slots}), disabling '{filter_name}'")
                self.toggle_autobrr_filter(filter_name, False)
            else:
                # Slots available, enable filter
                logger.info(f"[{label}] {available_slots} slot(s) available ({current_count}/{max_slots}), enabling '{filter_name}'")
                self.toggle_autobrr_filter(filter_name, True)
    
    def print_status_summary(self, torrents_by_label):
        """Print a clean status summary"""
        logger.info("=" * 70)
        logger.info("STATUS SUMMARY:")
        
        total_active = 0
        total_max = 0
        
        for label, config in FILTER_CONFIG.items():
            max_slots = config['max_slots']
            filter_name = config['filter_name']
            active_count = len(torrents_by_label.get(label, {}))
            
            total_active += active_count
            total_max += max_slots
            
            status_emoji = "✓" if active_count < max_slots else "✗"
            logger.info(f"  {status_emoji} {filter_name:25} {active_count}/{max_slots} slots")
        
        logger.info(f"  {'─' * 40}")
        logger.info(f"  {'TOTAL':27} {total_active}/{total_max} slots")
        logger.info("=" * 70)
    
    def run(self):
        """Main supervisor loop"""
        logger.info("=" * 70)
        logger.info("Torrent Racing Supervisor Started - Per-Filter Mode")
        logger.info(f"Ratio Threshold: {RATIO_THRESHOLD}")
        logger.info(f"Time Threshold: {TIME_THRESHOLD_DAYS} days")
        logger.info(f"Check Interval: {CHECK_INTERVAL}s")
        logger.info("Filter Configuration:")
        for label, config in FILTER_CONFIG.items():
            logger.info(f"  - {config['filter_name']:25} ({label}): {config['max_slots']} slot(s)")
        logger.info("=" * 70)
        
        # Initial connection
        if not self.connect_deluge():
            logger.error("Failed to connect to Deluge on startup. Retrying...")
            time.sleep(10)
            return self.run()
        
        # Get initial autobrr filters
        self.get_autobrr_filters()
        
        while True:
            try:
                # Get torrents grouped by label
                torrents_by_label = self.get_torrents_by_label()
                
                # Remove eligible torrents
                removed_by_label = self.remove_eligible_torrents(torrents_by_label)
                
                # Manage filter slots
                self.manage_filter_slots(torrents_by_label, removed_by_label)
                
                # Print status summary
                self.print_status_summary(torrents_by_label)
                
            except Exception as e:
                logger.error(f"Error in supervisor loop: {e}")
                import traceback
                logger.error(traceback.format_exc())
                # Try to reconnect to Deluge
                logger.info("Attempting to reconnect to Deluge...")
                self.connect_deluge()
            
            # Wait before next check
            time.sleep(CHECK_INTERVAL)


def main():
    supervisor = RacingSupervisor()
    supervisor.run()


if __name__ == "__main__":
    main()