#!/bin/bash

CLEANUP_INTERVAL="${CLEANUP_INTERVAL:-1800}"  # 30 minutes default

echo "SSD Cleanup Service starting..."
echo "  - Download path: ${SSD_DOWNLOAD_PATH:-/race/usenet}"
echo "  - Cleanup age: ${CLEANUP_AGE_HOURS:-6} hours"
echo "  - Check interval: ${CLEANUP_INTERVAL} seconds"
echo "  - Space threshold: ${SSD_SPACE_THRESHOLD:-80}%"

while true; do
    /usr/local/bin/ssd-cleanup.sh cleanup
    sleep "$CLEANUP_INTERVAL"
done