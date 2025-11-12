#!/bin/bash

# Automated Media Server Setup Script
# Sets up the complete Plex + Radarr + Sonarr + Prowlarr + YggTorrent stack

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================${NC}\n"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root for security reasons"
   exit 1
fi

# Check requirements
check_requirements() {
    print_header "Checking Requirements"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    print_success "Docker found"
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    print_success "Docker Compose found"
    
    # Check if user is in docker group
    if ! groups $USER | grep &>/dev/null '\bdocker\b'; then
        print_warning "User $USER is not in the docker group. You may need to run docker commands with sudo."
        print_warning "To fix this: sudo usermod -aG docker $USER && newgrp docker"
    fi
    
    # Check disk space (minimum 20GB)
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 20971520 ]]; then  # 20GB in KB
        print_warning "Less than 20GB available disk space. Consider freeing up space for media storage."
    fi
    
    print_success "Requirements check completed"
}

# Create directory structure
create_directories() {
    print_header "Creating Directory Structure"
    
    # Create main directories
    mkdir -p config/{plex,radarr,sonarr,prowlarr,overseerr,bazarr,fetcharr,ygege}
    mkdir -p downloads/{incomplete,complete}
    mkdir -p media/{movies,tv}
    
    print_success "Directory structure created"
    
    # Set permissions (PUID=1000, PGID=1000)
    print_status "Setting directory permissions..."
    sudo chown -R 1000:1000 config downloads media 2>/dev/null || {
        print_warning "Could not set ownership to 1000:1000. Containers may have permission issues."
        print_warning "If you encounter issues, run: sudo chown -R 1000:1000 config downloads media"
    }
    
    print_success "Permissions configured"
}

# Collect user credentials
collect_credentials() {
    print_header "Collecting User Credentials"
    
    # YggTorrent credentials
    echo -e "${BLUE}YggTorrent Configuration:${NC}"
    read -p "Enter your YggTorrent username: " YGG_USERNAME
    read -s -p "Enter your YggTorrent password: " YGG_PASSWORD
    echo
    
    # Plex token
    echo -e "\n${BLUE}Plex Configuration:${NC}"
    print_status "Please visit https://plex.tv/claim to get your claim token"
    print_status "You have 4 minutes to use the token after generating it"
    read -p "Enter your Plex claim token (starts with 'claim-'): " PLEX_CLAIM
    
    # Optional: Trakt credentials for recommendations
    echo -e "\n${BLUE}Trakt.tv Configuration (Optional):${NC}"
    print_status "Trakt.tv provides better recommendations and watch history sync"
    read -p "Do you have a Trakt.tv account? (y/n): " HAS_TRAKT
    
    if [[ $HAS_TRAKT == "y" || $HAS_TRAKT == "Y" ]]; then
        read -p "Enter your Trakt.tv username: " TRAKT_USERNAME
        read -s -p "Enter your Trakt.tv password: " TRAKT_PASSWORD
        echo
    fi
    
    print_success "Credentials collected"
}

# Create YggTorrent config
create_ygge_config() {
    print_status "Creating YggTorrent configuration..."
    
    cat > ./config/ygege/config.json << EOF
{
  "username": "$YGG_USERNAME",
  "password": "$YGG_PASSWORD",
  "passkey": "",
  "rss": "",
  "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  "timeout": 30,
  "delay": 1,
  "retries": 3
}
EOF
    
    print_success "YggTorrent configuration created"
}

# Update docker-compose with user values
update_docker_compose() {
    print_status "Updating Docker Compose configuration..."
    
    # Update Plex claim token in docker-compose.yml
    sed -i "s/PLEX_CLAIM=claim-xxxxxxxxxxxxxxxxxxxx/PLEX_CLAIM=$PLEX_CLAIM/" foundation_compose.yml
    
    print_success "Docker Compose configuration updated"
}

# Start containers
start_containers() {
    print_header "Starting Containers"
    
    print_status "Starting containers... This may take a few minutes to download images."
    docker-compose -f foundation_compose.yml up -d
    
    print_status "Waiting for containers to start..."
    sleep 30
    
    # Check if containers are running
    failed_containers=()
    containers=("plex" "deluge" "prowlarr" "ygege" "radarr" "sonarr" "overseerr" "bazarr" "fetcharr")
    
    for container in "${containers[@]}"; do
        if ! docker ps | grep -q $container; then
            failed_containers+=($container)
        fi
    done
    
    if [ ${#failed_containers[@]} -eq 0 ]; then
        print_success "All containers started successfully"
    else
        print_warning "Some containers failed to start: ${failed_containers[*]}"
        print_warning "Check logs with: docker-compose logs <container_name>"
    fi
}

# Display access information
display_access_info() {
    print_header "Setup Complete!"
    
    # Get the local IP
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}Your media server is ready!${NC}\n"
    echo -e "${BLUE}Web Interfaces:${NC}"
    echo -e "  Plex (Media Library):      http://$LOCAL_IP:32400/web"
    echo -e "  Overseerr (Requests):      http://$LOCAL_IP:5055"
    echo -e "  Radarr (Movies):           http://$LOCAL_IP:7878"
    echo -e "  Sonarr (TV Shows):         http://$LOCAL_IP:8989"
    echo -e "  Prowlarr (Indexers):       http://$LOCAL_IP:9696"
    echo -e "  Deluge (Downloads):        http://$LOCAL_IP:8112 (password: deluge)"
    echo -e "  Bazarr (Subtitles):        http://$LOCAL_IP:6767"
    echo -e "  Fetcharr (Watchlist):      http://$LOCAL_IP:8080"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "  1. Visit Plex and complete the initial setup"
    echo -e "  2. Add Movie library pointing to: /data/media/movies"
    echo -e "  3. Add TV Show library pointing to: /data/media/tv"
    echo -e "  4. Configure Prowlarr indexers (YggTorrent should auto-configure)"
    echo -e "  5. Connect Radarr/Sonarr to Prowlarr and Deluge"
    echo -e "  6. Configure Overseerr to connect to Plex, Radarr, and Sonarr"
    echo -e "  7. Set up quality profiles for 4K content"
    
    echo -e "\n${BLUE}Configuration Files:${NC}"
    echo -e "  Main config: ./foundation_compose.yml"
    echo -e "  Configs stored in: ./config/"
    echo -e "  Downloads: ./downloads/"
    echo -e "  Media library: ./media/"
    
    echo -e "\n${YELLOW}Important Notes:${NC}"
    echo -e "  - Your Plex claim token expires in 4 minutes after generation"
    echo -e "  - Configure hardlinks in Radarr/Sonarr to save storage space"
    echo -e "  - Set quality profiles to avoid massive REMUX files"
    echo -e "  - YggTorrent indexers may need manual verification in Prowlarr"
    
    print_success "Setup completed successfully!"
}

# Create systemd service for auto-start (optional)
create_systemd_service() {
    if [[ $1 == "y" || $1 == "Y" ]]; then
        print_status "Creating systemd service for auto-start..."
        
        SERVICE_DIR="$PWD"
        
        sudo tee /etc/systemd/system/media-server.service > /dev/null << EOF
[Unit]
Description=Media Server Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$SERVICE_DIR
ExecStart=/usr/bin/docker-compose -f foundation_compose.yml up -d
ExecStop=/usr/bin/docker-compose -f foundation_compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
        
        sudo systemctl daemon-reload
        sudo systemctl enable media-server.service
        
        print_success "Systemd service created. Media server will auto-start on boot."
        print_status "Service commands:"
        print_status "  Start:   sudo systemctl start media-server"
        print_status "  Stop:    sudo systemctl stop media-server"
        print_status "  Status:  sudo systemctl status media-server"
    fi
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    # Add cleanup commands if needed
}

# Main execution
main() {
    print_header "Automated Media Server Setup"
    print_status "This script will set up a complete media automation stack"
    print_status "Components: Plex, Radarr, Sonarr, Prowlarr, Deluge, YggTorrent, Overseerr, Bazarr"
    
    read -p "Do you want to continue? (y/n): " CONTINUE
    if [[ $CONTINUE != "y" && $CONTINUE != "Y" ]]; then
        print_status "Setup cancelled"
        exit 0
    fi
    
    # Run setup steps
    check_requirements
    create_directories
    collect_credentials
    create_ygge_config
    update_docker_compose
    start_containers
    
    # Optional systemd service
    echo -e "\n${BLUE}Auto-start Configuration:${NC}"
    read -p "Create systemd service to auto-start on boot? (y/n): " CREATE_SERVICE
    create_systemd_service $CREATE_SERVICE
    
    display_access_info
    
    # Create a simple management script
    cat > manage.sh << 'EOF'
#!/bin/bash
# Media Server Management Script

case "$1" in
    start)
        docker-compose -f foundation_compose.yml up -d
        echo "Media server started"
        ;;
    stop)
        docker-compose -f foundation_compose.yml down
        echo "Media server stopped"
        ;;
    restart)
        docker-compose -f foundation_compose.yml restart
        echo "Media server restarted"
        ;;
    update)
        docker-compose -f foundation_compose.yml pull
        docker-compose -f foundation_compose.yml up -d
        echo "Media server updated"
        ;;
    logs)
        docker-compose -f foundation_compose.yml logs -f $2
        ;;
    status)
        docker-compose -f foundation_compose.yml ps
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|update|logs [service]|status}"
        exit 1
        ;;
esac
EOF
    
    chmod +x manage.sh
    print_success "Management script created: ./manage.sh"
    
    cleanup
    
    echo -e "\n${GREEN}🎉 Setup Complete! Your automated media server is ready to use.${NC}"
    echo -e "${BLUE}Start requesting content through Overseerr and enjoy your automated media library!${NC}"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
