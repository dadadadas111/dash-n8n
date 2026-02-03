#!/bin/bash

################################################################################
# n8n Secrets Generation Script
################################################################################
# This script generates secure secrets required for n8n deployment:
# - N8N_ENCRYPTION_KEY: Encryption key for n8n credentials (must not be lost)
# - POSTGRES_PASSWORD: Password for PostgreSQL root user
# - POSTGRES_NON_ROOT_PASSWORD: Password for non-root PostgreSQL user
#
# The generated secrets are displayed to the terminal and must be manually
# copied to your .env file for security reasons (avoiding auto-writes to disk).
#
# Requirements: openssl (available on Linux, macOS, and most Unix-like systems)
################################################################################

set -e

# Color codes for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}Generated Secrets for n8n${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Generate N8N_ENCRYPTION_KEY (32 bytes, base64 encoded)
echo -e "${YELLOW}Generating N8N_ENCRYPTION_KEY...${NC}"
N8N_ENCRYPTION_KEY=$(openssl rand -base64 32)
echo -e "${GREEN}✓ Done${NC}"
echo ""

# Generate POSTGRES_PASSWORD (24 bytes, base64 encoded = ~32 characters)
echo -e "${YELLOW}Generating POSTGRES_PASSWORD...${NC}"
POSTGRES_PASSWORD=$(openssl rand -base64 24)
echo -e "${GREEN}✓ Done${NC}"
echo ""

# Generate POSTGRES_NON_ROOT_PASSWORD (24 bytes, base64 encoded = ~32 characters)
echo -e "${YELLOW}Generating POSTGRES_NON_ROOT_PASSWORD...${NC}"
POSTGRES_NON_ROOT_PASSWORD=$(openssl rand -base64 24)
echo -e "${GREEN}✓ Done${NC}"
echo ""

# Display generated secrets
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}Generated Secrets${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}"
echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
echo "POSTGRES_NON_ROOT_PASSWORD=${POSTGRES_NON_ROOT_PASSWORD}"
echo ""

# Display instructions
echo -e "${YELLOW}IMPORTANT INSTRUCTIONS${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo "1. Copy the secrets above to your .env file:"
echo "   - N8N_ENCRYPTION_KEY"
echo "   - POSTGRES_PASSWORD"
echo "   - POSTGRES_NON_ROOT_PASSWORD"
echo ""
echo -e "${RED}⚠ WARNING: Store the N8N_ENCRYPTION_KEY securely!${NC}"
echo "   If this key is lost, encrypted credentials cannot be recovered."
echo "   Keep a backup in a secure location."
echo ""
echo "2. Never commit .env to version control"
echo "3. Restrict .env file permissions: chmod 600 .env"
echo ""
echo -e "${GREEN}✓ Secrets generated successfully${NC}"
