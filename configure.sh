#!/bin/bash

# Post-Setup Configuration Script
# Automates API connections between services after initial container startup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Wait for service to be ready
wait_for_service() {
    local service_name=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:$port >/dev/null 2>&1; then
            print_success "$service_name is ready"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts - $service_name not ready yet..."
        sleep 10
        ((attempt++))
    done
    
    print_error "$service_name failed to start within expected time"
    return 1
}

# Get API key from service
get_api_key() {
    local service=$1
    local port=$2
    local config_path="./config/$service/config.xml"
    
    if [ -f "$config_path" ]; then
        local api_key=$(grep -oP '<ApiKey>\K[^<]+' "$config_path" 2>/dev/null || echo "")
        if [ -n "$api_key" ]; then
            echo "$api_key"
            return 0
        fi
    fi
    
    print_warning "Could not extract API key for $service. Please configure manually."
    return 1
}

# Configure Prowlarr to sync with Radarr/Sonarr
configure_prowlarr_apps() {
    print_header "Configuring Prowlarr Application Sync"
    
    local prowlarr_api=$(get_api_key "prowlarr" "9696")
    local radarr_api=$(get_api_key "radarr" "7878")
    local sonarr_api=$(get_api_key "sonarr" "8989")
    
    if [ -z "$prowlarr_api" ] || [ -z "$radarr_api" ] || [ -z "$sonarr_api" ]; then
        print_warning "API keys not available. Please configure Prowlarr apps manually:"
        print_status "1. Go to Prowlarr Settings → Apps"
        print_status "2. Add Radarr: http://radarr:7878"
        print_status "3. Add Sonarr: http://sonarr:8989"
        return 1
    fi
    
    # Configure Radarr app in Prowlarr
    print_status "Adding Radarr to Prowlarr..."
    curl -s -X POST "http://localhost:9696/api/v1/applications" \
        -H "X-Api-Key: $prowlarr_api" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Radarr",
            "implementation": "Radarr",
            "configContract": "RadarrSettings",
            "fields": [
                {"name": "baseUrl", "value": "http://radarr:7878"},
                {"name": "apiKey", "value": "'$radarr_api'"},
                {"name": "syncLevel", "value": "fullSync"}
            ]
        }' >/dev/null && print_success "Radarr added to Prowlarr" || print_warning "Failed to add Radarr to Prowlarr"
    
    # Configure Sonarr app in Prowlarr
    print_status "Adding Sonarr to Prowlarr..."
    curl -s -X POST "http://localhost:9696/api/v1/applications" \
        -H "X-Api-Key: $prowlarr_api" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Sonarr",
            "implementation": "Sonarr",
            "configContract": "SonarrSettings",
            "fields": [
                {"name": "baseUrl", "value": "http://sonarr:8989"},
                {"name": "apiKey", "value": "'$sonarr_api'"},
                {"name": "syncLevel", "value": "fullSync"}
            ]
        }' >/dev/null && print_success "Sonarr added to Prowlarr" || print_warning "Failed to add Sonarr to Prowlarr"
}

# Configure Deluge as download client
configure_download_clients() {
    print_header "Configuring Download Clients"
    
    local radarr_api=$(get_api_key "radarr" "7878")
    local sonarr_api=$(get_api_key "sonarr" "8989")
    
    if [ -n "$radarr_api" ]; then
        print_status "Adding Deluge to Radarr..."
        curl -s -X POST "http://localhost:7878/api/v3/downloadclient" \
            -H "X-Api-Key: $radarr_api" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Deluge",
                "implementation": "Deluge",
                "configContract": "DelugeSettings",
                "fields": [
                    {"name": "host", "value": "deluge"},
                    {"name": "port", "value": 8112},
                    {"name": "password", "value": "deluge"},
                    {"name": "movieCategory", "value": "radarr"}
                ]
            }' >/dev/null && print_success "Deluge added to Radarr" || print_warning "Failed to add Deluge to Radarr"
    fi
    
    if [ -n "$sonarr_api" ]; then
        print_status "Adding Deluge to Sonarr..."
        curl -s -X POST "http://localhost:8989/api/v3/downloadclient" \
            -H "X-Api-Key: $sonarr_api" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "Deluge",
                "implementation": "Deluge", 
                "configContract": "DelugeSettings",
                "fields": [
                    {"name": "host", "value": "deluge"},
                    {"name": "port", "value": 8112},
                    {"name": "password", "value": "deluge"},
                    {"name": "tvCategory", "value": "sonarr"}
                ]
            }' >/dev/null && print_success "Deluge added to Sonarr" || print_warning "Failed to add Deluge to Sonarr"
    fi
}

# Create optimized quality profiles
create_quality_profiles() {
    print_header "Creating Optimized Quality Profiles"
    
    local radarr_api=$(get_api_key "radarr" "7878")
    local sonarr_api=$(get_api_key "sonarr" "8989")
    
    print_status "Quality profiles need to be configured manually for best results:"
    print_status "Radarr: Edit Ultra-HD profile to prefer WEB-DL 2160p > Bluray 2160p (avoid REMUX)"
    print_status "Sonarr: Create similar profile prioritizing WEB-DL over REMUX"
    print_status "This avoids 100GB+ files while maintaining excellent quality"
}

# Display configuration summary
display_configuration_summary() {
    print_header "Configuration Summary"
    
    local services=("plex:32400" "radarr:7878" "sonarr:8989" "prowlarr:9696" "overseerr:5055" "deluge:8112" "bazarr:6767" "fetcharr:8080")
    
    echo -e "${GREEN}Service Status:${NC}"
    for service in "${services[@]}"; do
        local name=$(echo $service | cut -d: -f1)
        local port=$(echo $service | cut -d: -f2)
        
        if curl -s http://localhost:$port >/dev/null 2>&1; then
            echo -e "  ✅ $name (http://localhost:$port)"
        else
            echo -e "  ❌ $name (http://localhost:$port) - Not responding"
        fi
    done
    
    echo -e "\n${BLUE}Manual Configuration Required:${NC}"
    echo -e "  📖 Complete Plex setup and add libraries"
    echo -e "  🔗 Configure Overseerr connections to Plex/Radarr/Sonarr"
    echo -e "  🎯 Verify Prowlarr indexers are working"
    echo -e "  ⚙️  Set quality profiles to avoid REMUX files"
    echo -e "  📝 Configure Bazarr subtitle providers"
    
    echo -e "\n${YELLOW}Tips:${NC}"
        echo -e "  • Use 'docker compose logs <service>' or 'docker-compose logs <service>' to troubleshoot issues"
    echo -e "  • Enable hardlinks in Radarr/Sonarr to save storage"
    echo -e "  • Test with a popular movie first to verify the pipeline"
    echo -e "  • Set up quality profiles before adding large libraries"
}

# Main execution
main() {
    print_header "Post-Setup Configuration"
    print_status "Configuring service connections and API integrations..."
    
    # Wait for all services to be ready
    print_status "Checking service availability..."
    
    services=("prowlarr:9696" "radarr:7878" "sonarr:8989" "overseerr:5055")
    
    for service in "${services[@]}"; do
        local name=$(echo $service | cut -d: -f1)
        local port=$(echo $service | cut -d: -f2)
        wait_for_service $name $port || {
            print_warning "$name not ready - you'll need to configure manually"
        }
    done
    
    # Give services a bit more time to fully initialize
    print_status "Allowing services to complete initialization..."
    sleep 30
    
    # Configure integrations
    configure_prowlarr_apps
    configure_download_clients
    create_quality_profiles
    
    display_configuration_summary
    
    print_success "Post-setup configuration completed!"
    print_status "Your media server is ready for final manual configuration steps."
}

main "$@"
