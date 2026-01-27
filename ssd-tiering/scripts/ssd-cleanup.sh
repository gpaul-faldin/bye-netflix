#!/bin/bash
#
# SSD Cleanup Script for SABnzbd
# Removes completed downloads from SSD after Sonarr/Radarr import
#
# This script cleans up the SSD temp folder after files have been
# imported by Sonarr/Radarr to their final HDD destination.
#

set -euo pipefail

# Configuration
SSD_DOWNLOAD_PATH="${SSD_DOWNLOAD_PATH:-/race/usenet}"
CLEANUP_AGE_HOURS="${CLEANUP_AGE_HOURS:-6}"
LOG_FILE="${LOG_FILE:-/config/logs/ssd-cleanup.log}"
DRY_RUN="${DRY_RUN:-false}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

cleanup_old_files() {
    log "Starting SSD cleanup (files older than ${CLEANUP_AGE_HOURS}h)..."
    
    # Find and remove files older than CLEANUP_AGE_HOURS
    # Only remove video files and their associated files (srt, nfo, etc.)
    local extensions=("mkv" "mp4" "avi" "m4v" "srt" "sub" "idx" "nfo")
    local total_freed=0
    
    for ext in "${extensions[@]}"; do
        while IFS= read -r -d '' file; do
            if [[ -f "$file" ]]; then
                local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "[DRY-RUN] Would delete: $file ($(numfmt --to=iec $size))"
                else
                    rm -f "$file"
                    log "Deleted: $file ($(numfmt --to=iec $size))"
                fi
                
                total_freed=$((total_freed + size))
            fi
        done < <(find "$SSD_DOWNLOAD_PATH" -type f -name "*.$ext" -mmin +$((CLEANUP_AGE_HOURS * 60)) -print0 2>/dev/null)
    done
    
    # Remove empty directories
    if [[ "$DRY_RUN" != "true" ]]; then
        find "$SSD_DOWNLOAD_PATH/complete" -mindepth 2 -type d -empty -delete 2>/dev/null || true
    fi
    
    log "Cleanup complete. Freed: $(numfmt --to=iec $total_freed)"
}

cleanup_by_space() {
    # Emergency cleanup if SSD is getting full
    local threshold="${SSD_SPACE_THRESHOLD:-80}"
    local usage=$(df "$SSD_DOWNLOAD_PATH" | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [[ $usage -gt $threshold ]]; then
        log "WARNING: SSD usage at ${usage}% (threshold: ${threshold}%). Running emergency cleanup..."
        
        # Delete oldest files first until under threshold
        while [[ $usage -gt $threshold ]]; do
            local oldest=$(find "$SSD_DOWNLOAD_PATH" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) -printf '%T+ %p\n' 2>/dev/null | sort | head -1 | cut -d' ' -f2-)
            
            if [[ -z "$oldest" ]]; then
                log "No more files to delete, but still at ${usage}%"
                break
            fi
            
            local size=$(stat -c%s "$oldest" 2>/dev/null || echo 0)
            rm -f "$oldest"
            log "Emergency delete: $oldest ($(numfmt --to=iec $size))"
            
            usage=$(df "$SSD_DOWNLOAD_PATH" | awk 'NR==2 {print $5}' | tr -d '%')
        done
        
        log "Emergency cleanup complete. SSD now at ${usage}%"
    else
        log "SSD usage OK: ${usage}%"
    fi
}

show_status() {
    log "=== SSD Status ==="
    df -h "$SSD_DOWNLOAD_PATH"
    echo ""
    log "Files on SSD:"
    find "$SSD_DOWNLOAD_PATH" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) -printf '%T+ %s %p\n' 2>/dev/null | sort -r | head -20 | while read -r line; do
        log "  $line"
    done
}

# Main
case "${1:-cleanup}" in
    cleanup)
        cleanup_by_space
        cleanup_old_files
        ;;
    emergency)
        SSD_SPACE_THRESHOLD=50 cleanup_by_space
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {cleanup|emergency|status}"
        exit 1
        ;;
esac