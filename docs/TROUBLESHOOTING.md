# n8n Troubleshooting Guide

This guide helps you diagnose and resolve common issues with your n8n deployment.

---

## Table of Contents

1. [Common Issues](#common-issues)
2. [Diagnostic Commands](#diagnostic-commands)
3. [Backup and Restore Procedures](#backup-and-restore-procedures)
4. [Encryption Key Management](#encryption-key-management)
5. [Performance Tuning](#performance-tuning)
6. [Support Resources](#support-resources)

---

## Common Issues

### 🔴 Issue: Container Won't Start

**Symptoms:**
- Container shows "Restarting" status
- Container exits immediately after starting
- `docker compose ps` shows "Exited (1)"

**Diagnostic Steps:**

```bash
# Check container status
docker compose ps

# View container logs
docker compose logs postgres
docker compose logs redis
docker compose logs n8n
docker compose logs n8n-worker

# Check for specific errors
docker compose logs n8n | grep -i error
docker compose logs postgres | grep -i error
```

**Common Solutions:**

#### Solution 1: Missing or Invalid .env File

```bash
# Verify .env file exists
ls -la .env

# Check .env has all required variables
grep -E "POSTGRES_PASSWORD|N8N_ENCRYPTION_KEY|DB_POSTGRESDB_PASSWORD" .env

# If missing, copy from template
cp .env.example .env
nano .env
```

#### Solution 2: init-data.sh Permissions

```bash
# Check file exists and has execute permission
ls -la init-data.sh

# Set execute permission if missing
chmod +x init-data.sh

# Restart postgres
docker compose restart postgres
```

#### Solution 3: Disk Space Full

```bash
# Check disk space
df -h /var/lib/docker

# If full, clean up Docker
docker system prune -a
docker volume prune

# Remove old images
docker image prune -a
```

#### Solution 4: Port Already in Use

```bash
# Check if port 5678 is already in use
sudo netstat -tulpn | grep 5678
# OR
sudo lsof -i :5678

# If port is in use, either:
# 1. Stop the conflicting service
# 2. Change n8n port in docker-compose.yml
ports:
  - "8080:5678"  # Changed from 5678:5678
```

---

### 🔴 Issue: Database Connection Errors

**Symptoms:**
- n8n shows "Database connection failed"
- n8n logs: `Error: connect ECONNREFUSED`
- n8n container keeps restarting

**Diagnostic Steps:**

```bash
# Check postgres health
docker compose ps postgres

# View postgres logs
docker compose logs postgres

# Test postgres connection from n8n container
docker compose exec n8n sh -c 'nc -zv postgres 5432'
```

**Common Solutions:**

#### Solution 1: Mismatched Credentials

Verify credentials in `.env` match:

```bash
# These must match:
POSTGRES_NON_ROOT_PASSWORD=xxx
DB_POSTGRESDB_PASSWORD=xxx

# These must match:
POSTGRES_NON_ROOT_USER=n8n_user
DB_POSTGRESDB_USER=n8n_user

# These must match:
POSTGRES_DB=n8n
DB_POSTGRESDB_DATABASE=n8n
```

Edit `.env` to fix mismatches, then:

```bash
docker compose down
docker compose up -d
```

#### Solution 2: PostgreSQL Not Initialized

```bash
# Recreate postgres with fresh initialization
docker compose down
docker volume rm dash-n8n_postgres_data

# WARN: This deletes all data! Restore from backup after.
docker compose up -d postgres
sleep 20

# Check postgres logs for initialization
docker compose logs postgres | grep "database system is ready"
```

#### Solution 3: Check init-data.sh Execution

```bash
# View postgres logs for init script execution
docker compose logs postgres | grep "init-data.sh"

# If script failed, check its contents
cat init-data.sh

# Verify it creates the non-root user
grep "CREATE USER" init-data.sh
```

---

### 🔴 Issue: Webhooks Not Working

**Symptoms:**
- Webhook URLs return 404 or timeout
- External services can't reach webhooks
- Webhook test shows "Connection refused"

**Diagnostic Steps:**

```bash
# Check n8n configuration
docker compose exec n8n env | grep N8N_HOST
docker compose exec n8n env | grep WEBHOOK_URL

# Test webhook locally from server
curl -v http://localhost:5678/webhook-test/<webhook-path>

# Test from external network
curl -v http://your-domain.com:5678/webhook-test/<webhook-path>
```

**Common Solutions:**

#### Solution 1: Incorrect N8N_HOST and WEBHOOK_URL

Edit `.env` with correct values:

```bash
# For production with public domain:
N8N_HOST=n8n.yourdomain.com
N8N_PROTOCOL=https
WEBHOOK_URL=https://n8n.yourdomain.com

# For production with IP address:
N8N_HOST=123.45.67.89
N8N_PROTOCOL=http
WEBHOOK_URL=http://123.45.67.89:5678

# For local testing:
N8N_HOST=localhost
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:5678
```

Restart n8n:

```bash
docker compose restart n8n
```

#### Solution 2: Firewall Blocking Port 5678

```bash
# Check if port is open (on server)
sudo ufw status | grep 5678

# Open port if blocked
sudo ufw allow 5678/tcp
sudo ufw reload

# OR for iptables
sudo iptables -A INPUT -p tcp --dport 5678 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4
```

#### Solution 3: Reverse Proxy Configuration

If using Nginx/Caddy, verify proxy configuration:

**Nginx:**
```nginx
location / {
    proxy_pass http://localhost:5678;
    
    # REQUIRED for webhooks
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

Reload Nginx:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

---

### 🔴 Issue: Permission Denied Errors

**Symptoms:**
- Logs show "EACCES: permission denied"
- Containers can't write to volumes
- SSH deployment fails with "Permission denied (publickey)"

**Common Solutions:**

#### Solution 1: Volume Permissions

```bash
# Fix volume ownership
docker compose down
sudo chown -R 1000:1000 volumes/n8n_data

# Restart services
docker compose up -d
```

#### Solution 2: SSH Key Permissions

```bash
# Local machine: Fix SSH key permissions
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# Server: Fix authorized_keys permissions
ssh user@server "chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

#### Solution 3: init-data.sh Not Executable

```bash
# Set execute permission
chmod +x init-data.sh

# Restart postgres
docker compose restart postgres
```

---

### 🔴 Issue: Disk Space Full

**Symptoms:**
- Containers crash with "No space left on device"
- Docker commands hang or fail
- Server becomes unresponsive

**Diagnostic Steps:**

```bash
# Check disk space
df -h /
df -h /var/lib/docker

# Check Docker disk usage
docker system df
docker system df -v
```

**Solutions:**

#### Solution 1: Clean Docker Resources

```bash
# Remove stopped containers, unused networks, dangling images
docker system prune -a

# Remove unused volumes (CAUTION: May delete data)
docker volume prune

# Remove specific old images
docker images
docker rmi <image-id>
```

#### Solution 2: Clean Old Backups

```bash
# List backups
ls -lh backups/

# Remove backups older than 30 days
find backups/ -name "n8n_backup_*.sql" -mtime +30 -delete
```

#### Solution 3: Increase Disk Space

- Expand server disk (cloud provider console)
- Resize partition: `sudo resize2fs /dev/sda1`
- Mount additional volume for Docker data

---

### 🔴 Issue: High Memory or CPU Usage

**Symptoms:**
- Server slow or unresponsive
- OOM (Out of Memory) killer terminates containers
- Workflows take very long to execute

**Diagnostic Steps:**

```bash
# Monitor real-time resource usage
docker stats

# Check specific container usage
docker stats n8n-main n8n-worker

# View system resources
htop
# OR
top

# Check for memory leaks in logs
docker compose logs n8n | grep -i "memory\|heap"
```

**Solutions:**

#### Solution 1: Increase Resource Limits

Edit `docker-compose.yml`:

```yaml
n8n:
  deploy:
    resources:
      limits:
        memory: 4G  # Increased from 2G
        cpus: '4'   # Increased from 2
```

Apply changes:

```bash
docker compose up -d
```

#### Solution 2: Scale Worker Replicas

```bash
# Increase workers to distribute load
docker compose up -d --scale n8n-worker=3

# Verify workers running
docker compose ps | grep worker
```

#### Solution 3: Optimize Workflows

- Reduce polling frequency for trigger nodes
- Use webhooks instead of polling where possible
- Split large workflows into smaller ones
- Add "Wait" nodes to throttle execution
- Review and disable unused active workflows

#### Solution 4: Enable Swap (If No Swap Configured)

```bash
# Check swap
free -h

# Create 4GB swap file
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Diagnostic Commands

### Service Status

```bash
# All services
docker compose ps

# Detailed status with health
docker compose ps --format json | jq '.[] | {name:.Service, status:.Status, health:.Health}'

# Check specific service
docker compose ps n8n
```

### Logs

```bash
# All services (last 100 lines)
docker compose logs --tail=100

# Follow logs in real-time
docker compose logs -f

# Specific service
docker compose logs n8n
docker compose logs postgres
docker compose logs redis
docker compose logs n8n-worker

# Filter for errors
docker compose logs n8n | grep -i error
docker compose logs n8n | grep -i warning

# Last 50 lines with timestamps
docker compose logs --tail=50 --timestamps n8n
```

### Health Checks

```bash
# Check n8n health endpoint
curl -f http://localhost:5678/healthz && echo "n8n: healthy" || echo "n8n: unhealthy"

# Check PostgreSQL
docker compose exec postgres pg_isready -U postgres

# Check Redis
docker compose exec redis redis-cli ping

# Check all service health
docker compose ps --format '{{.Service}}\t{{.Status}}\t{{.Health}}'
```

### Resource Usage

```bash
# Real-time resource monitoring
docker stats

# Specific containers
docker stats n8n-main n8n-worker postgres redis

# One-time snapshot
docker stats --no-stream

# Disk usage
docker system df

# Detailed volume info
docker volume ls
docker volume inspect dash-n8n_n8n_data
```

### Network Connectivity

```bash
# Test container-to-container connectivity
docker compose exec n8n ping -c 3 postgres
docker compose exec n8n ping -c 3 redis

# Test port connectivity
docker compose exec n8n nc -zv postgres 5432
docker compose exec n8n nc -zv redis 6379

# View network details
docker network inspect dash-n8n_n8n_network
```

---

## Backup and Restore Procedures

### Automated Backup

Run the backup script:

```bash
# Basic backup
bash scripts/backup-postgres.sh

# With 30-day retention
bash scripts/backup-postgres.sh --retention-days 30

# Backup location
ls -lh backups/
```

**Set up automated daily backups** with cron:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * cd /opt/n8n && bash scripts/backup-postgres.sh --retention-days 30 >> /var/log/n8n-backup.log 2>&1
```

### Manual Backup

```bash
# Backup PostgreSQL database
docker exec dash-n8n-postgres-1 pg_dump \
    -U postgres \
    -d n8n \
    --clean --if-exists \
    > backups/manual_backup_$(date +%Y%m%d_%H%M%S).sql

# Backup n8n data volume
docker run --rm \
    -v dash-n8n_n8n_data:/data \
    -v $(pwd)/backups:/backup \
    alpine tar czf /backup/n8n_data_$(date +%Y%m%d_%H%M%S).tar.gz /data
```

### Restore from Backup

#### 1. Stop Services

```bash
docker compose down
```

#### 2. Restore Database

```bash
# Start postgres only
docker compose up -d postgres
sleep 10

# List available backups
ls -lh backups/

# Restore from specific backup
docker exec -i dash-n8n-postgres-1 psql \
    -U postgres \
    -d n8n \
    < backups/n8n_backup_20260203_120000.sql

# Verify restore
docker exec dash-n8n-postgres-1 psql -U postgres -d n8n -c "SELECT COUNT(*) FROM public.workflow_entity;"
```

#### 3. Restore n8n Data Volume (If Needed)

```bash
# Stop services
docker compose down

# Restore volume from backup
docker run --rm \
    -v dash-n8n_n8n_data:/data \
    -v $(pwd)/backups:/backup \
    alpine sh -c "cd /data && tar xzf /backup/n8n_data_20260203_120000.tar.gz --strip-components=1"
```

#### 4. Restart All Services

```bash
docker compose up -d

# Verify health
docker compose ps
docker compose logs -f
```

### Backup to S3 (Optional)

Enable S3 uploads by adding to `.env`:

```bash
# AWS S3 bucket for backups
S3_BUCKET=my-n8n-backups
```

Install AWS CLI on server:

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install awscli

# Configure AWS credentials
aws configure
```

Run backup (will automatically upload to S3):

```bash
bash scripts/backup-postgres.sh --retention-days 30
```

---

## Encryption Key Management

### ⚠️ CRITICAL: Understanding Encryption Keys

**The `N8N_ENCRYPTION_KEY` encrypts ALL credentials stored in n8n.**

- **If lost:** All saved credentials (API keys, passwords, tokens) become **permanently unrecoverable**
- **If changed:** Existing credentials cannot be decrypted (new workflows will use new key)
- **Best practice:** Generate once, back up securely, **never change**

### Backing Up Encryption Key

```bash
# Method 1: Copy from .env to password manager
grep N8N_ENCRYPTION_KEY .env

# Method 2: Store in encrypted file
gpg -c .env
# Creates .env.gpg (encrypted backup)

# Method 3: Store in secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.)
```

### Recovering Lost Encryption Key

**If you lose the encryption key, there is NO recovery method.**

Your options:
1. **Restore from backup** (if you backed up `.env` file)
2. **Start fresh** (lose all saved credentials):
   ```bash
   # Generate new encryption key
   openssl rand -hex 32
   
   # Update .env with new key
   N8N_ENCRYPTION_KEY=new_generated_key
   
   # All existing workflows will need credentials re-entered
   ```

### Changing Encryption Key (Advanced)

**⚠️ WARNING:** Only do this if absolutely necessary. Requires re-entering ALL credentials.

```bash
# 1. Export all workflows
# (Use n8n UI: Settings → Workflows → Export All)

# 2. Stop n8n
docker compose down

# 3. Generate new encryption key
openssl rand -hex 32

# 4. Update .env with new key
nano .env

# 5. Clear database credentials (keeps workflows)
docker exec dash-n8n-postgres-1 psql -U postgres -d n8n -c "DELETE FROM credentials_entity;"

# 6. Restart n8n
docker compose up -d

# 7. Re-import workflows and re-enter all credentials
```

---

## Performance Tuning

### Optimize PostgreSQL

Edit `docker-compose.yml`:

```yaml
postgres:
  environment:
    # Add performance tuning
    - POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C
  command:
    - postgres
    - -c
    - shared_buffers=256MB
    - -c
    - max_connections=200
```

### Optimize Redis

```yaml
redis:
  command:
    - redis-server
    - --maxmemory 512mb
    - --maxmemory-policy allkeys-lru
```

### Scale Workers

```bash
# Increase to 3 workers for higher throughput
docker compose up -d --scale n8n-worker=3
```

### Monitor Performance

```bash
# Install monitoring tools
docker run -d \
  --name cadvisor \
  -p 8080:8080 \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  google/cadvisor:latest
```

---

## Support Resources

### Official Documentation
- **n8n Documentation**: https://docs.n8n.io/
- **n8n Hosting Guide**: https://docs.n8n.io/hosting/
- **n8n Environment Variables**: https://docs.n8n.io/hosting/configuration/environment-variables/

### Community Support
- **n8n Community Forum**: https://community.n8n.io/
- **n8n Discord**: https://discord.gg/n8n
- **n8n GitHub Issues**: https://github.com/n8n-io/n8n/issues

### Docker Resources
- **Docker Documentation**: https://docs.docker.com/
- **Docker Compose Reference**: https://docs.docker.com/compose/compose-file/
- **PostgreSQL Docker Hub**: https://hub.docker.com/_/postgres

### Getting Help

When asking for help, provide:

1. **n8n version**: `docker compose exec n8n n8n --version`
2. **Error logs**: `docker compose logs n8n | tail -50`
3. **Environment details**:
   - OS: `uname -a`
   - Docker: `docker --version`
   - Docker Compose: `docker compose version`
4. **Steps to reproduce** the issue
5. **What you've already tried**

---

## Quick Reference

### Start/Stop Services

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# Restart all services
docker compose restart

# Restart specific service
docker compose restart n8n
```

### Update n8n

```bash
docker compose pull
docker compose up -d
```

### View Logs

```bash
docker compose logs -f
```

### Backup

```bash
bash scripts/backup-postgres.sh
```

### Health Check

```bash
docker compose ps
curl http://localhost:5678/healthz
```

---

**Still having issues?** Visit the [n8n community forum](https://community.n8n.io/) for help!
