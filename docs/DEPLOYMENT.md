# n8n Deployment Guide

This guide walks you through deploying n8n to your server using the automated deployment scripts.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Platform-Specific Deployment](#platform-specific-deployment)
   - [Production Deployment with SSL (Recommended)](#production-deployment-with-ssl-recommended)
   - [Basic Deployment (Development)](#basic-deployment-development)
   - [Windows Deployment](#windows-deployment-powershell)
   - [Linux/macOS Deployment](#linuxmacos-deployment-bash)
4. [Post-Deployment Verification](#post-deployment-verification)
5. [Updating n8n](#updating-n8n)
6. [Rollback Procedure](#rollback-procedure)
7. [Advanced Configuration](#advanced-configuration)

---

## Prerequisites

### ✅ Prerequisites Checklist

Before deploying, ensure you have:

- [ ] **Docker Engine 20.10+** installed on target server
- [ ] **Docker Compose 2.0+** installed on target server
- [ ] **Nginx** installed on target server (for production with SSL)
- [ ] **SSH access** to server with key-based authentication configured
- [ ] **Sudo privileges** on server (required for Nginx and SSL setup)
- [ ] **Server meets minimum requirements**:
  - 2 CPU cores
  - 4 GB RAM
  - 20 GB disk space
- [ ] **Ports open** on server firewall:
  - 80 (HTTP - required for Let's Encrypt verification)
  - 443 (HTTPS - for production)
  - 22 (SSH)
  - ~~5678 (n8n UI)~~ - **NOT needed for production** (Nginx handles external access)
- [ ] **Domain name** pointed to server (required for SSL)
- [ ] **Email address** for SSL certificate notifications
- [ ] **SSH client** on local machine:
  - Windows: OpenSSH (built-in on Windows 10 1809+)
  - Linux/macOS: OpenSSH (pre-installed)

### Verify Server Prerequisites

SSH to your server and run:

```bash
# Check Docker
docker --version
# Expected: Docker version 20.10.0 or higher

# Check Docker Compose
docker compose version
# Expected: Docker Compose version 2.0.0 or higher

# Check Nginx (for production deployment)
nginx -v
# Expected: nginx version 1.18.0 or higher
# If not installed: sudo apt update && sudo apt install -y nginx

# Check disk space
df -h /
# Expected: At least 20GB available

# Check RAM
free -h
# Expected: At least 4GB total

# Verify DNS (replace with your domain)
dig n8n.yourdomain.com +short
# Expected: Should return your server's public IP address
```

---

## Initial Setup

### Step 1: Clone Repository

On your local machine:

```bash
git clone <repository-url>
cd dash-n8n
```

### Step 2: Generate Secrets

Run the secret generation script:

```bash
# Linux/macOS/Git Bash on Windows
bash scripts/generate-secrets.sh
```

**Output will show:**
```
=============================================
Generated Secrets for n8n
=============================================

N8N_ENCRYPTION_KEY=a1b2c3d4e5f6...
POSTGRES_PASSWORD=XyZ123AbC...
POSTGRES_NON_ROOT_PASSWORD=qRs456TuV...

Copy these values to your .env file.
WARNING: Store the encryption key securely!
=============================================
```

**⚠️ IMPORTANT:** Copy these values immediately - you'll need them in the next step!

### Step 3: Create .env File

```bash
# Create .env from template
cp .env.example .env

# Edit with your text editor
nano .env
# OR
vim .env
# OR on Windows
notepad .env
```

**Update these values in .env:**

```bash
# 1. PostgreSQL Passwords (from generate-secrets.sh output)
POSTGRES_PASSWORD=paste_generated_password_here
POSTGRES_NON_ROOT_PASSWORD=paste_generated_password_here

# 2. n8n Encryption Key (from generate-secrets.sh output)
N8N_ENCRYPTION_KEY=paste_generated_encryption_key_here

# 3. Database password (must match POSTGRES_NON_ROOT_PASSWORD)
DB_POSTGRESDB_PASSWORD=same_as_POSTGRES_NON_ROOT_PASSWORD

# 4. Server Configuration
N8N_HOST=your-domain.com  # or server IP address
WEBHOOK_URL=http://your-domain.com:5678  # or https:// if using reverse proxy

# 5. Timezone (optional - default is America/New_York)
GENERIC_TIMEZONE=Your/Timezone
TZ=Your/Timezone
```

**For production with HTTPS (recommended):**
```bash
N8N_PROTOCOL=https
N8N_HOST=n8n.yourdomain.com
WEBHOOK_URL=https://n8n.yourdomain.com
```

**Note:** These values will be automatically updated by the deployment script when you deploy with `--ssl` flag.

### Step 4: Configure SSH Key Authentication

If you don't already have an SSH key:

```bash
# Generate new SSH key
ssh-keygen -t ed25519 -C "n8n-deployment"

# Press Enter to accept default location (~/.ssh/id_ed25519)
# Optionally set a passphrase (recommended)
```

Copy your public key to the server:

```bash
# Linux/macOS/Git Bash
ssh-copy-id username@your-server.com

# OR manually:
cat ~/.ssh/id_ed25519.pub | ssh username@your-server.com "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# Windows PowerShell (if ssh-copy-id not available)
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh username@your-server.com "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Test SSH connection:

```bash
ssh username@your-server.com "echo 'SSH connection successful'"
```

**Expected output:** `SSH connection successful`

---

## Platform-Specific Deployment

Choose your deployment method based on your local operating system and desired configuration.

---

### Production Deployment with SSL (Recommended)

For production environments, deploy with Nginx reverse proxy and Let's Encrypt SSL certificates.

**Requirements:**
- Domain name pointed to your server's IP
- Ports 80 and 443 open in firewall
- Email address for SSL notifications
- Nginx installed on server
- Sudo privileges on server

#### Linux/macOS Production Deployment

```bash
bash scripts/deploy-linux.sh \
    --server your-server.com \
    --user your-username \
    --domain n8n.yourdomain.com \
    --ssl \
    --email admin@yourdomain.com
```

#### Windows Production Deployment

```powershell
.\scripts\deploy-windows.ps1 `
    -Server "your-server.com" `
    -User "your-username" `
    -Domain "n8n.yourdomain.com" `
    -EnableSSL `
    -Email "admin@yourdomain.com"
```

#### What This Does

1. **Uploads all files** to server (docker-compose, .env, scripts, nginx config)
2. **Deploys Docker containers** (n8n, postgres, redis)
3. **Configures Nginx** as reverse proxy
4. **Obtains SSL certificate** from Let's Encrypt
5. **Sets up auto-renewal** for SSL certificates
6. **Configures HTTP → HTTPS redirect**
7. **Updates .env** with HTTPS URLs
8. **Restarts services** to apply configuration

#### Expected Output

```bash
[INFO] n8n Deployment Configuration
========================================
Server:        your-username@your-server.com
Domain:        n8n.yourdomain.com
SSL Enabled:   true
SSL Email:     admin@yourdomain.com
========================================

[INFO] Verifying local deployment files...
[SUCCESS] All required files present

[INFO] Testing SSH connectivity...
[SUCCESS] SSH connectivity verified

[INFO] Uploading deployment files...
[SUCCESS] Files uploaded successfully

[INFO] Pulling latest Docker images...
[SUCCESS] Docker images pulled

[INFO] Deploying n8n services...
[SUCCESS] Services deployed

[INFO] Setting up Nginx reverse proxy...
[INFO] Configuring Nginx (this may take a few minutes)...
[INFO] Validating DNS configuration...
[SUCCESS] DNS points to correct server

[INFO] Installing certbot...
[INFO] Obtaining SSL certificate...
[SUCCESS] SSL certificate obtained successfully

[INFO] Configuring SSL auto-renewal...
[SUCCESS] Nginx configured successfully

[INFO] Updating .env with production HTTPS URL...
[INFO] Restarting n8n services to apply configuration...
[SUCCESS] Configuration updated

========================================
Deployment Complete!
========================================
Access your n8n instance at: https://n8n.yourdomain.com
SSL certificate automatically renews via certbot
```

#### Production Deployment Checklist

After deployment, verify:

- [ ] n8n accessible at `https://your-domain.com`
- [ ] HTTP redirects to HTTPS
- [ ] SSL certificate valid (green padlock in browser)
- [ ] WebSocket connections work (test with workflow execution)
- [ ] Certificate auto-renewal configured: `ssh user@server 'sudo certbot renew --dry-run'`

---

### Basic Deployment (Development)

For development or testing without SSL.

**⚠️ WARNING:** This exposes n8n over HTTP. Not recommended for production use.

---

### Windows Deployment (PowerShell)

#### Basic Deployment (HTTP Only)

Open PowerShell and run:

```powershell
.\scripts\deploy-windows.ps1 `
    -Server "your-server.com" `
    -User "your-username" `
    -RemotePath "/opt/n8n"
```

#### With Custom SSH Key

```powershell
.\scripts\deploy-windows.ps1 `
    -Server "your-server.com" `
    -User "your-username" `
    -KeyPath "$env:USERPROFILE\.ssh\custom_key" `
    -RemotePath "/opt/n8n"
```

#### Dry-Run (Preview Commands)

```powershell
.\scripts\deploy-windows.ps1 `
    -Server "your-server.com" `
    -User "your-username" `
    -DryRun
```

#### Script Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `-Server` | Yes | Target server hostname or IP | - |
| `-User` | Yes | SSH username | - |
| `-KeyPath` | No | Path to SSH private key | `$env:USERPROFILE\.ssh\id_ed25519` |
| `-RemotePath` | No | Deployment directory on server | `/opt/n8n` |
| `-Domain` | No | Domain name for Nginx configuration | - |
| `-EnableSSL` | No | Enable SSL with Let's Encrypt (requires `-Domain` and `-Email`) | `$false` |
| `-Email` | No | Email for SSL certificate notifications (required with `-EnableSSL`) | - |
| `-DryRun` | No | Preview commands without executing | `$false` |

#### Expected Output

```
INFO: Validating prerequisites...
INFO: Checking OpenSSH installation...
SUCCESS: OpenSSH found
INFO: Verifying local files...
SUCCESS: All required files found

INFO: Uploading files to your-server.com:/opt/n8n...
docker-compose.yml    100%
.env                  100%
init-data.sh          100%

SUCCESS: Files uploaded

INFO: Setting permissions on remote files...
SUCCESS: Permissions set

INFO: Pulling Docker images...
[+] Pulling...
SUCCESS: Images pulled

INFO: Deploying Docker Compose stack...
[+] Running 4/4
 ✔ Container n8n-postgres  Healthy
 ✔ Container n8n-redis     Healthy
 ✔ Container n8n-main      Healthy
 ✔ Container n8n-worker    Healthy

SUCCESS: Deployment completed!

n8n is now accessible at: http://your-server.com:5678
```

---

### Linux/macOS Deployment (Bash)

#### Basic Deployment (HTTP Only)

```bash
bash scripts/deploy-linux.sh \
    --server your-server.com \
    --user your-username \
    --remote-path /opt/n8n
```

#### With Custom SSH Key

```bash
bash scripts/deploy-linux.sh \
    --server your-server.com \
    --user your-username \
    --key ~/.ssh/custom_key \
    --remote-path /opt/n8n
```

#### Dry-Run (Preview Commands)

```bash
bash scripts/deploy-linux.sh \
    --server your-server.com \
    --user your-username \
    --dry-run
```

#### Script Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `--server` | Yes | Target server hostname or IP | - |
| `--user` | Yes | SSH username | - |
| `--key` | No | Path to SSH private key | `~/.ssh/id_ed25519` |
| `--remote-path` | No | Deployment directory on server | `/opt/n8n` |
| `--domain` | No | Domain name for Nginx configuration | - |
| `--ssl` | No | Enable SSL with Let's Encrypt (requires `--domain` and `--email`) | (disabled) |
| `--email` | No | Email for SSL certificate notifications (required with `--ssl`) | - |
| `--dry-run` | No | Preview commands without executing | (disabled) |
| `--help` | No | Show usage information | - |

#### Expected Output

```
[INFO] Validating prerequisites...
[INFO] Verifying local files...
[SUCCESS] All required files found

[INFO] Testing SSH connection to your-server.com...
[SUCCESS] SSH connection successful

[INFO] Uploading files via rsync...
sending incremental file list
docker-compose.yml
.env
init-data.sh

[SUCCESS] Files uploaded

[INFO] Verifying Docker installation on remote server...
[SUCCESS] Docker is installed

[INFO] Pulling Docker images...
[+] Pulling 4/4
[SUCCESS] Images pulled

[INFO] Deploying Docker Compose stack...
[+] Running 4/4
 ✔ Container n8n-postgres  Started
 ✔ Container n8n-redis     Started
 ✔ Container n8n-main      Started
 ✔ Container n8n-worker    Started

[INFO] Waiting 30s for services to stabilize...

[INFO] Checking service health status...
[SUCCESS] n8n: healthy
[SUCCESS] postgres: healthy
[SUCCESS] redis: healthy
[SUCCESS] n8n-worker: healthy

[SUCCESS] Deployment completed successfully!

Next steps:
  1. Access n8n: http://your-server.com:5678
  2. Create your admin account
  3. View logs: ssh your-username@your-server.com "cd /opt/n8n && docker compose logs -f"
```

---

## Post-Deployment Verification

### 1. Check Service Status

SSH to your server:

```bash
ssh username@your-server.com
cd /opt/n8n
docker compose ps
```

**Expected output:**
```
NAME          IMAGE                             STATUS              PORTS
n8n-main      docker.n8n.io/n8nio/n8n:1.70.3   Up (healthy)        0.0.0.0:5678->5678/tcp
n8n-worker    docker.n8n.io/n8nio/n8n:1.70.3   Up (healthy)
postgres      postgres:16-alpine                Up (healthy)
redis         redis:7-alpine                    Up (healthy)
```

All containers should show `Up (healthy)` status.

### 2. View Logs

```bash
# All services
docker compose logs

# Follow logs in real-time
docker compose logs -f

# Specific service
docker compose logs n8n
docker compose logs postgres
```

### 3. Access n8n UI

Open your browser and navigate to:

**Production (with SSL):** `https://n8n.yourdomain.com`  
**Development (HTTP only):** `http://your-server.com:5678`

You should see the n8n setup page prompting you to create an admin account.

**Security Check (for production SSL):**
- Browser should show a green padlock icon
- Certificate should be valid
- HTTP should automatically redirect to HTTPS

### 4. Create Admin Account

1. Fill in your admin credentials
2. Set up your account
3. You'll be redirected to the n8n workflow editor

### 5. Test Workflow (Optional)

Create a simple test workflow:

1. Add a "Schedule Trigger" node (run every 5 minutes)
2. Add an "HTTP Request" node (GET https://httpbin.org/json)
3. Add a "Set" node to extract data
4. Activate the workflow
5. Check execution history to verify it runs

---

## Updating n8n

### Update to Latest Version

SSH to your server:

```bash
ssh username@your-server.com
cd /opt/n8n

# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Verify health
docker compose ps

# Check logs for any issues
docker compose logs -f n8n
```

### Update to Specific Version

Edit `docker-compose.yml` on server:

```yaml
# Change this line:
image: docker.n8n.io/n8nio/n8n:1.70.3

# To specific version:
image: docker.n8n.io/n8nio/n8n:1.75.0
```

Then update:

```bash
docker compose up -d
docker compose ps
```

### Zero-Downtime Updates (Queue Mode)

Because this setup uses queue mode with a main container and worker:

1. Main container update is brief (~5-10 seconds downtime)
2. Worker continues processing queued jobs during update
3. New jobs are queued in Redis until main container restarts
4. Workers automatically reconnect to updated main container

---

## Rollback Procedure

If an update causes issues, rollback to the previous version:

### 1. Stop Services

```bash
ssh username@your-server.com
cd /opt/n8n
docker compose down
```

### 2. Restore Database Backup

```bash
# List available backups
ls -lh backups/

# Restore from specific backup
docker compose up -d postgres
sleep 10

docker exec -i dash-n8n-postgres-1 psql \
    -U postgres \
    -d n8n \
    < backups/n8n_backup_20260203_120000.sql
```

### 3. Revert docker-compose.yml (if version changed)

Edit `docker-compose.yml`:

```yaml
# Change back to previous version:
image: docker.n8n.io/n8nio/n8n:1.70.3
```

### 4. Restart All Services

```bash
docker compose up -d
docker compose ps
docker compose logs -f
```

---

## Advanced Configuration

### Manual Nginx Configuration

If you deployed without `--ssl` flag but want to add SSL later:

#### Step 1: Configure Nginx Manually

```bash
# On your server
cd /opt/n8n

# Make setup script executable
chmod +x scripts/setup-nginx.sh

# Run setup (HTTP only)
sudo ./scripts/setup-nginx.sh --domain n8n.yourdomain.com --deployment-dir /opt/n8n

# Or with SSL
sudo ./scripts/setup-nginx.sh --domain n8n.yourdomain.com --deployment-dir /opt/n8n --ssl --email admin@yourdomain.com
```

#### Step 2: Update .env for HTTPS

```bash
# Edit .env file
nano .env

# Update these lines:
N8N_PROTOCOL=https
N8N_HOST=n8n.yourdomain.com
WEBHOOK_URL=https://n8n.yourdomain.com

# Restart services
docker compose restart n8n n8n-worker
```

### SSL Certificate Management

#### Check Certificate Status

```bash
sudo certbot certificates
```

#### Manual Certificate Renewal

```bash
# Test renewal (dry-run)
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal
```

#### Auto-Renewal Configuration

The deployment script automatically configures a systemd timer for certificate renewal. Verify it:

```bash
# Check renewal timer status
sudo systemctl status certbot.timer

# View renewal logs
sudo journalctl -u certbot.renew.service
```
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Enable and restart Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Enable HTTPS with Let's Encrypt

```bash
# Install certbot
sudo apt update
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d n8n.yourdomain.com

# Update .env on server
N8N_PROTOCOL=https
N8N_HOST=n8n.yourdomain.com
WEBHOOK_URL=https://n8n.yourdomain.com

# Restart n8n
docker compose up -d
```

### Custom Webhook URL

If using a reverse proxy or custom domain, update `.env`:

```bash
N8N_HOST=n8n.yourdomain.com
WEBHOOK_URL=https://n8n.yourdomain.com
N8N_PROTOCOL=https
```

Restart services:

```bash
docker compose up -d
```

### Scaling Workers

To increase concurrent workflow execution, scale the worker service.

Edit `docker-compose.yml`:

```yaml
n8n-worker:
  # ... existing config ...
  deploy:
    replicas: 3  # Run 3 worker containers
```

Apply changes:

```bash
docker compose up -d --scale n8n-worker=3
docker compose ps
```

---

## Troubleshooting

If you encounter issues during deployment, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for:

- Common deployment errors and solutions
- Diagnostic commands
- Service health check procedures
- Log analysis tips

---

## Next Steps

- ✅ Deployment complete
- ⏭️ [Set up automated backups](./TROUBLESHOOTING.md#backup-and-restore-procedures)
- ⏭️ [Configure webhook authentication](#custom-webhook-url)
- ⏭️ [Explore n8n workflows](https://docs.n8n.io/workflows/)

---

**Questions?** Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) or visit the [n8n community forum](https://community.n8n.io/).
