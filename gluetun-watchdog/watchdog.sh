#!/bin/sh

echo "[$(date)] Deluge Watchdog started - monitoring connectivity"

FAILURE_COUNT=0
RESTART_COUNT=0
MAX_FAILURES=3  # Restart after 3 consecutive failures
DELUGE_URL="http://gluetun:8112"  # Access via gluetun container which exposes Deluge's port

while true; do
    # Check if Deluge WebUI is accessible through Gluetun
    if wget --spider --timeout=5 --tries=1 "$DELUGE_URL" > /dev/null 2>&1; then
        # Deluge is accessible
        if [ $FAILURE_COUNT -gt 0 ]; then
            echo "[$(date)] Deluge recovered, resetting failure count"
            FAILURE_COUNT=0
        fi
    else
        # Deluge is not accessible
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "[$(date)] WARNING: Deluge unreachable at $DELUGE_URL (failure $FAILURE_COUNT/$MAX_FAILURES)"

        if [ $FAILURE_COUNT -ge $MAX_FAILURES ]; then
            RESTART_COUNT=$((RESTART_COUNT + 1))
            echo "[$(date)] Deluge unreachable for $MAX_FAILURES consecutive checks"
            echo "[$(date)] Restarting Deluge (restart #$RESTART_COUNT)..."

            if docker restart deluge 2>&1; then
                echo "[$(date)] Deluge restarted successfully"
                FAILURE_COUNT=0
                sleep 30  # Give it time to start up before checking again
            else
                echo "[$(date)] ERROR: Failed to restart Deluge"
                FAILURE_COUNT=0  # Reset to avoid spam
                sleep 10
            fi
        fi
    fi

    sleep 10
done
