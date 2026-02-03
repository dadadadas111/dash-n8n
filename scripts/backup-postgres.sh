#!/bin/bash
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load credentials from .env file
if [ -f .env ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Configuration
BACKUP_DIR="backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/n8n_backup_$TIMESTAMP.sql"
RETENTION_DAYS="${1:-}"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Log function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
}

log "INFO" "${GREEN}Starting PostgreSQL backup...${NC}"

# Detect container name from docker-compose
# Try to get the postgres service container name
POSTGRES_CONTAINER=$(docker ps --filter "label=com.docker.compose.service=postgres" --format "{{.Names}}" 2>/dev/null | head -1)

if [ -z "$POSTGRES_CONTAINER" ]; then
    # Fallback: use common naming pattern
    POSTGRES_CONTAINER="dash-n8n-postgres-1"
    if ! docker ps --format "{{.Names}}" | grep -q "$POSTGRES_CONTAINER"; then
        log "ERROR" "${RED}Could not find PostgreSQL container. Is Docker Compose running?${NC}"
        exit 1
    fi
fi

log "INFO" "Using container: $POSTGRES_CONTAINER"

# Perform backup
if docker exec "$POSTGRES_CONTAINER" pg_dump \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --clean --if-exists \
    > "$BACKUP_FILE" 2>&1; then
    
    FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "INFO" "${GREEN}Backup completed successfully${NC}"
    log "INFO" "Backup file: $BACKUP_FILE (${FILE_SIZE})"
else
    log "ERROR" "${RED}Backup failed${NC}"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Optional S3 upload
if command -v aws &> /dev/null && [ -n "${S3_BUCKET:-}" ]; then
    log "INFO" "Attempting S3 upload to s3://$S3_BUCKET/n8n-backups/"
    if aws s3 cp "$BACKUP_FILE" "s3://$S3_BUCKET/n8n-backups/" 2>&1; then
        log "INFO" "${GREEN}S3 upload successful${NC}"
    else
        log "ERROR" "${YELLOW}S3 upload failed (backup still saved locally)${NC}"
    fi
elif command -v aws &> /dev/null; then
    log "INFO" "${YELLOW}AWS CLI available but S3_BUCKET not configured. Skipping S3 upload.${NC}"
elif [ -n "${S3_BUCKET:-}" ]; then
    log "INFO" "${YELLOW}S3_BUCKET configured but AWS CLI not found. Skipping S3 upload.${NC}"
fi

# Optional retention policy
if [ -n "$RETENTION_DAYS" ]; then
    log "INFO" "Applying retention policy: keeping last $RETENTION_DAYS days of backups"
    find "$BACKUP_DIR" -name "n8n_backup_*.sql" -mtime "+$RETENTION_DAYS" -delete
    log "INFO" "${GREEN}Old backups deleted${NC}"
fi

log "INFO" "${GREEN}Backup process completed${NC}"
