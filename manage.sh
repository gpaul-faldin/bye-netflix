#!/bin/bash
# Media Server Management Script
COMPOSE_CMD="docker compose"

case "$1" in
    start)
        eval "$COMPOSE_CMD -f docker.compose.yml up -d"
        echo "Media server started"
        ;;
    stop)
        eval "$COMPOSE_CMD -f docker.compose.yml down"
        echo "Media server stopped"
        ;;
    restart)
        eval "$COMPOSE_CMD -f docker.compose.yml restart"
        echo "Media server restarted"
        ;;
    update)
        eval "$COMPOSE_CMD -f docker.compose.yml pull"
        eval "$COMPOSE_CMD -f docker.compose.yml up -d"
        echo "Media server updated"
        ;;
    logs)
        SERVICE="$2"
        if [[ -n "$SERVICE" ]]; then
            eval "$COMPOSE_CMD -f docker.compose.yml logs -f $SERVICE"
        else
            eval "$COMPOSE_CMD -f docker.compose.yml logs --no-color"
        fi
        ;;
    status)
        eval "$COMPOSE_CMD -f docker.compose.yml ps"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|update|logs [service]|status}"
        exit 1
        ;;
esac
