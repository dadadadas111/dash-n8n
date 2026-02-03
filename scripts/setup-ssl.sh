#!/bin/bash
#
# Setup SSL Certificate for n8n with Let's Encrypt
# This script configures Certbot and obtains SSL certificates
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN=""
EMAIL=""

# Usage
usage() {
    cat << EOF
Usage: $0 --domain <domain> --email <email>

Setup SSL certificate for n8n with Let's Encrypt

Required arguments:
    --domain DOMAIN     Your n8n domain (e.g., n8n.example.com)
    --email EMAIL       Email for Let's Encrypt notifications

Example:
    $0 --domain n8n.example.com --email admin@example.com

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown argument '$1'${NC}"
            usage
            ;;
    esac
done

# Validate arguments
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: --domain and --email are required${NC}"
    usage
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}n8n SSL Certificate Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Domain: ${GREEN}$DOMAIN${NC}"
echo -e "Email:  ${GREEN}$EMAIL${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Step 1: Install Certbot
echo -e "${BLUE}[1/5] Checking Certbot installation...${NC}"
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Certbot not found. Installing...${NC}"
    
    # Detect OS
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    elif [ -f /etc/redhat-release ]; then
        yum install -y certbot python3-certbot-nginx
    else
        echo -e "${RED}Error: Unsupported OS. Please install certbot manually.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Certbot installed${NC}"
else
    echo -e "${GREEN}✓ Certbot already installed${NC}"
fi

# Step 2: Check DNS resolution
echo -e "${BLUE}[2/5] Verifying DNS resolution...${NC}"
if ! host "$DOMAIN" > /dev/null 2>&1; then
    echo -e "${RED}Error: Domain '$DOMAIN' does not resolve to an IP address${NC}"
    echo -e "${YELLOW}Please ensure:${NC}"
    echo -e "  1. DNS A record points to this server's IP"
    echo -e "  2. DNS changes have propagated (can take up to 48 hours)"
    exit 1
fi

SERVER_IP=$(host "$DOMAIN" | grep "has address" | head -1 | awk '{print $NF}')
echo -e "${GREEN}✓ Domain resolves to: $SERVER_IP${NC}"

# Step 3: Check Nginx is running
echo -e "${BLUE}[3/5] Checking Nginx status...${NC}"
if ! systemctl is-active --quiet nginx; then
    echo -e "${YELLOW}Nginx is not running. Starting...${NC}"
    systemctl start nginx
fi

if ! systemctl is-enabled --quiet nginx; then
    systemctl enable nginx
fi

echo -e "${GREEN}✓ Nginx is running${NC}"

# Step 4: Test Nginx configuration
echo -e "${BLUE}[4/5] Testing Nginx configuration...${NC}"
if ! nginx -t > /dev/null 2>&1; then
    echo -e "${RED}Error: Nginx configuration test failed${NC}"
    nginx -t
    exit 1
fi
echo -e "${GREEN}✓ Nginx configuration is valid${NC}"

# Step 5: Obtain SSL certificate
echo -e "${BLUE}[5/5] Obtaining SSL certificate from Let's Encrypt...${NC}"

if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo -e "${YELLOW}Certificate already exists for $DOMAIN${NC}"
    echo -e "${YELLOW}Renewing certificate...${NC}"
    certbot renew --nginx --non-interactive
else
    echo -e "${YELLOW}Requesting new certificate...${NC}"
    certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --domain "$DOMAIN" \
        --redirect
fi

# Check if certificate was obtained successfully
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo -e "${GREEN}✓ SSL certificate obtained successfully${NC}"
else
    echo -e "${RED}Error: Failed to obtain SSL certificate${NC}"
    exit 1
fi

# Step 6: Setup auto-renewal
echo -e "${BLUE}[6/6] Setting up automatic renewal...${NC}"

# Certbot installs a systemd timer for auto-renewal by default
if systemctl list-timers | grep -q certbot; then
    echo -e "${GREEN}✓ Certbot auto-renewal timer is active${NC}"
else
    echo -e "${YELLOW}Setting up cron job for auto-renewal...${NC}"
    
    # Add cron job if not exists
    CRON_CMD="0 3 * * * certbot renew --nginx --quiet && systemctl reload nginx"
    (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "$CRON_CMD") | crontab -
    
    echo -e "${GREEN}✓ Cron job added for daily renewal check at 3 AM${NC}"
fi

# Display certificate info
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSL Certificate Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Certificate details:"
certbot certificates | grep -A 10 "$DOMAIN"
echo ""
echo -e "${GREEN}Your n8n instance is now accessible at:${NC}"
echo -e "${BLUE}https://$DOMAIN${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Update your .env file:"
echo -e "     ${BLUE}N8N_PROTOCOL=https${NC}"
echo -e "     ${BLUE}N8N_HOST=$DOMAIN${NC}"
echo -e "     ${BLUE}WEBHOOK_URL=https://$DOMAIN${NC}"
echo ""
echo -e "  2. Restart n8n containers:"
echo -e "     ${BLUE}cd /opt/n8n && docker compose restart${NC}"
echo ""
echo -e "${GREEN}Certificate will auto-renew before expiry.${NC}"
