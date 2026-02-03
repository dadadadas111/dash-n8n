#!/bin/bash
set -euo pipefail

# Trap errors and report line number
trap 'echo -e "${RED}Error on line $LINENO${NC}" >&2; exit 1' ERR

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_KEY="$HOME/.ssh/id_ed25519"
DEFAULT_REMOTE_PATH="/opt/n8n"
DRY_RUN=false

# Required parameters (will be validated)
SERVER=""
USER=""
KEY="$DEFAULT_KEY"
REMOTE_PATH="$DEFAULT_REMOTE_PATH"

# Optional Nginx/SSL parameters
DOMAIN=""
ENABLE_SSL=false
SSL_EMAIL=""

# Usage function
usage() {
    cat <<EOF
${BLUE}n8n Linux Deployment Script${NC}

Usage: $0 --server <hostname> --user <username> [OPTIONS]

Required:
  --server <hostname>       Target server hostname or IP address
  --user <username>         SSH username for remote access

Optional:
  --key <path>              SSH private key path (default: ~/.ssh/id_ed25519)
  --remote-path <path>      Remote deployment directory (default: /opt/n8n)
  --domain <domain>         Domain name for Nginx configuration
  --ssl                     Enable SSL with Let's Encrypt (requires --domain and --email)
  --email <email>           Email for SSL certificate notifications
  --dry-run                 Show commands without executing
  --help                    Show this help message

Example (Basic deployment):
  $0 --server n8n.example.com --user deploy

Example (Production with SSL):
  $0 --server n8n.example.com --user deploy --domain n8n.example.com --ssl --email admin@example.com

Services deployed:
  - n8n (main instance)
  - n8n-worker (queue worker)
  - postgres (database)
  - redis (queue backend)

Production features (with --ssl):
  - Nginx reverse proxy with SSL
  - Let's Encrypt SSL certificates
  - Automatic HTTP to HTTPS redirect
  - WebSocket support for n8n

EOF
    exit 0
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            SERVER="$2"
            shift 2
            ;;
        --user)
            USER="$2"
            shift 2
            ;;
        --key)
            KEY="$2"
            shift 2
            ;;
        --remote-path)
            REMOTE_PATH="$2"
            shift 2
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --ssl)
            ENABLE_SSL=true
            shift
            ;;
        --email)
            SSL_EMAIL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$SERVER" ]]; then
    log_error "Missing required parameter: --server"
    echo "Use --help for usage information"
    exit 1
fi

if [[ -z "$USER" ]]; then
    log_error "Missing required parameter: --user"
    echo "Use --help for usage information"
    exit 1
fi

# Validate SSL parameters
if [[ "$ENABLE_SSL" == "true" ]]; then
    if [[ -z "$DOMAIN" ]]; then
        log_error "--ssl requires --domain to be specified"
        exit 1
    fi
    if [[ -z "$SSL_EMAIL" ]]; then
        log_error "--ssl requires --email to be specified for Let's Encrypt notifications"
        exit 1
    fi
fi

# If domain is specified without SSL, warn user
if [[ -n "$DOMAIN" && "$ENABLE_SSL" == "false" ]]; then
    log_warning "Domain specified without --ssl flag. Nginx will be configured for HTTP only."
    log_warning "For production use, add --ssl flag to enable HTTPS."
fi

# Validate SSH key exists
if [[ ! -f "$KEY" ]]; then
    log_error "SSH key not found: $KEY"
    exit 1
fi

# Display deployment configuration
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}n8n Deployment Configuration${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Server:        ${GREEN}${USER}@${SERVER}${NC}"
echo -e "SSH Key:       ${KEY}"
echo -e "Remote Path:   ${REMOTE_PATH}"
echo -e "Dry Run:       ${DRY_RUN}"
if [[ -n "$DOMAIN" ]]; then
    echo -e "Domain:        ${GREEN}${DOMAIN}${NC}"
    echo -e "SSL Enabled:   ${ENABLE_SSL}"
    if [[ "$ENABLE_SSL" == "true" ]]; then
        echo -e "SSL Email:     ${SSL_EMAIL}"
    fi
fi
echo -e "${BLUE}========================================${NC}"
echo ""

# Dry-run helper function
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $1"
    else
        eval "$1"
    fi
}

# Step 1: Verify local files exist
log_info "Verifying local deployment files..."
REQUIRED_FILES=("docker-compose.yml" ".env" "init-data.sh")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        MISSING_FILES+=("$file")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    log_error "Missing required files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    exit 1
fi
log_success "All required files present"

# Step 2: Test SSH connectivity
log_info "Testing SSH connectivity to ${USER}@${SERVER}..."
SSH_CMD="ssh -i \"$KEY\" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"
if [[ "$DRY_RUN" == "false" ]]; then
    if ! $SSH_CMD "${USER}@${SERVER}" "echo 'SSH connection successful'" > /dev/null 2>&1; then
        log_error "Cannot establish SSH connection to ${USER}@${SERVER}"
        log_error "Please verify:"
        log_error "  1. Server is reachable"
        log_error "  2. SSH key is authorized"
        log_error "  3. User has appropriate permissions"
        exit 1
    fi
fi
log_success "SSH connectivity verified"

# Step 3: Create remote directory if needed
log_info "Ensuring remote directory exists: $REMOTE_PATH"
run_cmd "$SSH_CMD \"${USER}@${SERVER}\" \"mkdir -p ${REMOTE_PATH}\""
log_success "Remote directory ready"

# Step 4: Upload files using rsync with scp fallback
log_info "Uploading deployment files to ${SERVER}:${REMOTE_PATH}..."

# Determine files to upload
FILES_TO_UPLOAD=("docker-compose.yml" ".env" "init-data.sh")

# If domain is specified, also upload nginx directory and setup scripts
if [[ -n "$DOMAIN" ]]; then
    FILES_TO_UPLOAD+=("scripts/setup-nginx.sh")
    if [[ "$ENABLE_SSL" == "true" ]]; then
        FILES_TO_UPLOAD+=("scripts/setup-ssl.sh")
    fi
    # We need to upload nginx config template
    if [[ -d "nginx" ]]; then
        FILES_TO_UPLOAD+=("nginx")
    fi
fi

RSYNC_CMD="rsync -avz --delete \
    -e \"ssh -i $KEY -o StrictHostKeyChecking=accept-new\" \
    ${FILES_TO_UPLOAD[*]} \
    \"${USER}@${SERVER}:${REMOTE_PATH}/\""

if [[ "$DRY_RUN" == "false" ]]; then
    if command -v rsync &> /dev/null; then
        if ! eval "$RSYNC_CMD"; then
            log_warning "rsync failed, falling back to scp..."
            for file in "${FILES_TO_UPLOAD[@]}"; do
                if [[ -d "$file" ]]; then
                    scp -i "$KEY" -o StrictHostKeyChecking=accept-new -r "$file" "${USER}@${SERVER}:${REMOTE_PATH}/"
                else
                    scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$file" "${USER}@${SERVER}:${REMOTE_PATH}/"
                fi
            done
        fi
    else
        log_warning "rsync not found, using scp..."
        for file in "${FILES_TO_UPLOAD[@]}"; do
            if [[ -d "$file" ]]; then
                scp -i "$KEY" -o StrictHostKeyChecking=accept-new -r "$file" "${USER}@${SERVER}:${REMOTE_PATH}/"
            else
                scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$file" "${USER}@${SERVER}:${REMOTE_PATH}/"
            fi
        done
    fi
else
    echo -e "${YELLOW}[DRY-RUN]${NC} $RSYNC_CMD"
fi
log_success "Files uploaded successfully"

# Step 5: Verify Docker is available on remote server
log_info "Verifying Docker installation on remote server..."
DOCKER_CHECK="$SSH_CMD \"${USER}@${SERVER}\" \"command -v docker && docker compose version\""
if [[ "$DRY_RUN" == "false" ]]; then
    if ! eval "$DOCKER_CHECK" > /dev/null 2>&1; then
        log_error "Docker or Docker Compose not found on remote server"
        log_error "Please install Docker and Docker Compose on ${SERVER}"
        exit 1
    fi
fi
log_success "Docker installation verified"

# Step 6: Pull latest Docker images
log_info "Pulling latest Docker images on remote server..."
DOCKER_PULL_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"cd ${REMOTE_PATH} && docker compose pull\""
run_cmd "$DOCKER_PULL_CMD"
log_success "Docker images pulled"

# Step 7: Deploy services
log_info "Deploying n8n services..."
DOCKER_UP_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"cd ${REMOTE_PATH} && docker compose up -d --remove-orphans\""
run_cmd "$DOCKER_UP_CMD"
log_success "Services deployed"

# Step 8: Wait for services to stabilize
if [[ "$DRY_RUN" == "false" ]]; then
    log_info "Waiting for services to stabilize (30 seconds)..."
    sleep 30
fi

# Step 9: Check service status
log_info "Checking service status..."
DOCKER_PS_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"cd ${REMOTE_PATH} && docker compose ps\""
run_cmd "$DOCKER_PS_CMD"

# Step 10: Setup Nginx if domain is specified
if [[ -n "$DOMAIN" ]]; then
    log_info "Setting up Nginx reverse proxy..."
    
    # Make setup scripts executable
    CHMOD_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"chmod +x ${REMOTE_PATH}/scripts/setup-nginx.sh\""
    if [[ "$ENABLE_SSL" == "true" ]]; then
        CHMOD_CMD="$CHMOD_CMD && chmod +x ${REMOTE_PATH}/scripts/setup-ssl.sh"
    fi
    run_cmd "$CHMOD_CMD"
    
    # Build nginx setup command
    NGINX_SETUP_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"cd ${REMOTE_PATH} && sudo ./scripts/setup-nginx.sh --domain ${DOMAIN} --deployment-dir ${REMOTE_PATH}\""
    
    if [[ "$ENABLE_SSL" == "true" ]]; then
        NGINX_SETUP_CMD="${NGINX_SETUP_CMD} --ssl --email ${SSL_EMAIL}"
    fi
    
    # Run nginx setup
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Configuring Nginx (this may take a few minutes)..."
        if ! eval "$NGINX_SETUP_CMD"; then
            log_error "Nginx setup failed"
            log_error "n8n services are running but not accessible via domain"
            log_error "Check logs on server: ${REMOTE_PATH}/scripts/setup-nginx.sh"
            exit 1
        fi
        log_success "Nginx configured successfully"
        
        # Update .env with production URL if SSL is enabled
        if [[ "$ENABLE_SSL" == "true" ]]; then
            log_info "Updating .env with production HTTPS URL..."
            UPDATE_ENV_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"cd ${REMOTE_PATH} && sed -i 's|^N8N_PROTOCOL=.*|N8N_PROTOCOL=https|' .env && sed -i 's|^N8N_HOST=.*|N8N_HOST=${DOMAIN}|' .env\""
            run_cmd "$UPDATE_ENV_CMD"
            
            # Restart n8n to apply new URL settings
            log_info "Restarting n8n services to apply configuration..."
            RESTART_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"cd ${REMOTE_PATH} && docker compose restart n8n n8n-worker\""
            run_cmd "$RESTART_CMD"
            
            if [[ "$DRY_RUN" == "false" ]]; then
                sleep 10  # Wait for services to restart
            fi
            log_success "Configuration updated"
        fi
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} $NGINX_SETUP_CMD"
    fi
fi

# Step 11: Verify health checks
log_info "Verifying service health..."
HEALTH_CHECK_CMD="$SSH_CMD \"${USER}@${SERVER}\" \"cd ${REMOTE_PATH} && docker compose ps --format json\""

if [[ "$DRY_RUN" == "false" ]]; then
    HEALTH_OUTPUT=$(eval "$HEALTH_CHECK_CMD")
    
    # Parse health status for each service
    UNHEALTHY_SERVICES=()
    for service in n8n n8n-worker postgres redis; do
        if echo "$HEALTH_OUTPUT" | grep -q "\"Service\":\"$service\""; then
            HEALTH_STATUS=$(echo "$HEALTH_OUTPUT" | grep "\"Service\":\"$service\"" | grep -o '"Health":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$HEALTH_STATUS" && "$HEALTH_STATUS" != "healthy" ]]; then
                UNHEALTHY_SERVICES+=("$service ($HEALTH_STATUS)")
            fi
        fi
    done
    
    if [[ ${#UNHEALTHY_SERVICES[@]} -gt 0 ]]; then
        log_warning "Some services are not yet healthy:"
        for service in "${UNHEALTHY_SERVICES[@]}"; do
            echo "  - $service"
        done
        log_warning "Services may still be starting up. Check logs with:"
        echo "  ssh -i $KEY ${USER}@${SERVER} 'cd ${REMOTE_PATH} && docker compose logs -f'"
    else
        log_success "All services are healthy"
    fi
else
    echo -e "${YELLOW}[DRY-RUN]${NC} $HEALTH_CHECK_CMD"
fi

# Final summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Services: n8n, n8n-worker, postgres, redis"
echo -e "Location: ${USER}@${SERVER}:${REMOTE_PATH}"

if [[ -n "$DOMAIN" ]]; then
    echo ""
    if [[ "$ENABLE_SSL" == "true" ]]; then
        echo -e "${GREEN}Access your n8n instance at: https://${DOMAIN}${NC}"
        echo -e "SSL certificate automatically renews via certbot"
    else
        echo -e "${GREEN}Access your n8n instance at: http://${DOMAIN}${NC}"
        echo -e "${YELLOW}WARNING: HTTP only. For production, redeploy with --ssl flag${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo -e "  View logs:    ssh -i $KEY ${USER}@${SERVER} 'cd ${REMOTE_PATH} && docker compose logs -f'"
echo -e "  Check status: ssh -i $KEY ${USER}@${SERVER} 'cd ${REMOTE_PATH} && docker compose ps'"
echo -e "  Restart:      ssh -i $KEY ${USER}@${SERVER} 'cd ${REMOTE_PATH} && docker compose restart'"
echo -e "  Stop:         ssh -i $KEY ${USER}@${SERVER} 'cd ${REMOTE_PATH} && docker compose down'"

if [[ -n "$DOMAIN" && "$ENABLE_SSL" == "true" ]]; then
    echo ""
    echo -e "${BLUE}SSL Management:${NC}"
    echo -e "  Renew SSL:    ssh -i $KEY ${USER}@${SERVER} 'sudo certbot renew'"
    echo -e "  SSL status:   ssh -i $KEY ${USER}@${SERVER} 'sudo certbot certificates'"
fi

echo -e "${BLUE}========================================${NC}"
