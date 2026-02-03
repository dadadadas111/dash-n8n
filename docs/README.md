# n8n Self-Hosting Solution

> **Production-ready n8n deployment with Docker Compose, PostgreSQL, Redis, Nginx reverse proxy with SSL, and automated cross-platform deployment scripts.**

## 📋 Overview

This project provides a complete, production-ready solution for self-hosting [n8n](https://n8n.io/) - a powerful workflow automation platform. It includes:

- **Docker Compose stack** with n8n, PostgreSQL 16, and Redis 7
- **Queue mode** for concurrent workflow execution with dedicated worker processes
- **Nginx reverse proxy** with automatic SSL certificate provisioning via Let's Encrypt
- **Cross-platform deployment scripts** for Windows (PowerShell) and Linux/macOS (Bash)
- **Automated backup scripts** for PostgreSQL with optional S3 upload
- **Comprehensive documentation** for setup, deployment, and troubleshooting

### Key Features

✅ **Production Architecture**: n8n main + worker containers with Redis queue mode for high concurrency  
✅ **SSL/HTTPS Ready**: One-command deployment with automatic SSL certificate provisioning  
✅ **Nginx Reverse Proxy**: Automatic configuration with WebSocket support and security headers  
✅ **Persistent Data**: PostgreSQL 16 for reliable data storage (workflows, credentials, execution history)  
✅ **Health Checks**: All services monitored with Docker health checks and graceful startup ordering  
✅ **Cross-Platform**: Deploy from Windows, Linux, or macOS to any Linux server  
✅ **Security-First**: No hardcoded credentials, encryption key management, SSH key authentication  
✅ **One-Command Deploy**: Automated scripts handle file uploads, Docker commands, Nginx config, and SSL setup  

### Who Should Use This

- Developers wanting to self-host n8n for personal or team use
- Teams needing production-ready n8n deployment
- Anyone looking for a complete, documented n8n self-hosting solution
- Organizations requiring full control over their automation infrastructure

---

## 🏗️ Architecture

```
                        ┌─────────────────────────────────────┐
                        │         Internet/Users              │
                        └───────────────┬─────────────────────┘
                                        │
                                 HTTPS (443) / HTTP (80)
                                        │
┌───────────────────────────────────────▼─────────────────────────────────┐
│                            Docker Host (VPS)                             │
│                                                                          │
│  ┌──────────────────┐                                                   │
│  │  Nginx (Host)    │  ← Reverse Proxy + SSL Termination               │
│  │  Port 80/443     │                                                   │
│  └────────┬─────────┘                                                   │
│           │ localhost:5678                                              │
│           │                                                              │
│  ┌────────▼────────┐  ┌─────────────┐  ┌───────────┐                  │
│  │  n8n Main       │  │ n8n Worker  │  │  Redis    │                  │
│  │  (Web UI)       │◄─┤ (Background │◄─┤  (Queue)  │                  │
│  │  127.0.0.1:5678 │  │   Jobs)     │  │           │                  │
│  └──────┬──────────┘  └──────┬──────┘  └───────────┘                  │
│         │                    │                                          │
│         └──────────┬─────────┘                                          │
│                    │                                                     │
│            ┌───────▼────────┐                                           │
│            │ PostgreSQL 16  │                                           │
│            │   (Database)   │                                           │
│            └────────────────┘                                           │
│                                                                          │
│  Volumes: postgres_data, redis_data, n8n_data                           │
│  SSL Certificates: /etc/letsencrypt (managed by certbot)                │
└──────────────────────────────────────────────────────────────────────────┘
```

**Data Flow:**
1. User accesses n8n via domain (e.g., https://n8n.yourdomain.com)
2. Nginx handles SSL termination and proxies to n8n-main (localhost:5678)
3. Workflow executions queued to Redis
4. n8n-worker processes jobs from Redis queue
5. All data persisted to PostgreSQL (workflows, credentials, history)
6. Persistent volumes ensure data survives container restarts
7. Let's Encrypt certificates auto-renew via certbot

---

## ✅ Prerequisites

### Local Machine (Where You Deploy From)
- **Git** (to clone this repository)
- **SSH client** (OpenSSH on Windows 10 1809+, Linux, macOS)
- **SSH key** for server authentication (password-less login)

### Target Server (Where n8n Runs)
- **Operating System**: Ubuntu 20.04+ or Debian 11+ (any Linux with Docker support)
- **Docker Engine**: 20.10+ installed and running
- **Docker Compose**: 2.0+ installed
- **Nginx**: 1.18+ (for production SSL deployment)
- **SSH Server**: OpenSSH with key-based authentication enabled
- **Sudo privileges**: Required for Nginx and SSL certificate management
- **Minimum Hardware**:
  - 2 CPU cores
  - 4 GB RAM
  - 20 GB disk space
  - Open ports: 80 (HTTP), 443 (HTTPS), 22 (SSH)
- **Domain name**: Required for SSL (must point to server's public IP)

---

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone <repository-url>
cd dash-n8n
```

### 2. Generate Secrets
```bash
# Linux/macOS/Git Bash
bash scripts/generate-secrets.sh

# Output will show generated passwords - copy them for next step
```

### 3. Configure Environment
```bash
# Create .env file from template
cp .env.example .env

# Edit .env with your generated secrets
nano .env  # or vim, or any text editor

# Required changes:
# - N8N_ENCRYPTION_KEY: Paste generated key
# - POSTGRES_PASSWORD: Paste generated password
# - POSTGRES_NON_ROOT_PASSWORD: Paste generated password
# - N8N_HOST: Your domain or server IP
# - WEBHOOK_URL: Full URL to your n8n instance
```

### 4. Set Up SSH Access
```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "n8n-deployment"

# Copy key to server
ssh-copy-id user@your-server.com

# Test connection
ssh user@your-server.com "echo 'SSH connection successful'"
```

### 5. Deploy to Server

#### Production Deployment with SSL (Recommended)

**Windows (PowerShell):**
```powershell
.\scripts\deploy-windows.ps1 `
    -Server "your-server.com" `
    -User "your-username" `
    -Domain "n8n.yourdomain.com" `
    -EnableSSL `
    -Email "admin@yourdomain.com"
```

**Linux/macOS (Bash):**
```bash
bash scripts/deploy-linux.sh \
    --server your-server.com \
    --user your-username \
    --domain n8n.yourdomain.com \
    --ssl \
    --email admin@yourdomain.com
```

This will:
- Deploy all Docker containers
- Configure Nginx reverse proxy
- Obtain SSL certificate from Let's Encrypt
- Set up automatic certificate renewal
- Configure HTTP → HTTPS redirect

#### Development Deployment (HTTP Only)

**Windows (PowerShell):**
```powershell
.\scripts\deploy-windows.ps1 `
    -Server "your-server.com" `
    -User "your-username" `
    -RemotePath "/opt/n8n"
```

**Linux/macOS (Bash):**
```bash
bash scripts/deploy-linux.sh \
    --server your-server.com \
    --user your-username \
    --remote-path /opt/n8n
```

### 6. Access n8n

**Production (with SSL):**
- Open browser: `https://n8n.yourdomain.com`
- Verify SSL certificate (green padlock)

**Development (HTTP only):**
- Open browser: `http://your-server.com:5678`

Create your first admin account and start building workflows! 🎉

**For detailed deployment instructions**, see [DEPLOYMENT.md](./DEPLOYMENT.md).

---

## 🔐 Environment Variables Reference

| Variable | Required | Description | Default / Example |
|----------|----------|-------------|-------------------|
| **PostgreSQL Configuration** | | | |
| `POSTGRES_USER` | Yes | PostgreSQL root user | `postgres` |
| `POSTGRES_PASSWORD` | Yes | PostgreSQL root password | (generate strong password) |
| `POSTGRES_DB` | Yes | Database name for n8n | `n8n` |
| `POSTGRES_NON_ROOT_USER` | Yes | Application database user | `n8n_user` |
| `POSTGRES_NON_ROOT_PASSWORD` | Yes | Application user password | (generate strong password) |
| **n8n Database Configuration** | | | |
| `DB_TYPE` | Yes | Database type | `postgresdb` |
| `DB_POSTGRESDB_HOST` | Yes | PostgreSQL hostname | `postgres` (Docker service name) |
| `DB_POSTGRESDB_PORT` | Yes | PostgreSQL port | `5432` |
| `DB_POSTGRESDB_DATABASE` | Yes | Database name (matches POSTGRES_DB) | `n8n` |
| `DB_POSTGRESDB_USER` | Yes | Database user (matches POSTGRES_NON_ROOT_USER) | `n8n_user` |
| `DB_POSTGRESDB_PASSWORD` | Yes | Database password (matches POSTGRES_NON_ROOT_PASSWORD) | (same as above) |
| **Queue Configuration** | | | |
| `EXECUTIONS_MODE` | Yes | Execution mode (use `queue` for production) | `queue` |
| `QUEUE_BULL_REDIS_HOST` | Yes | Redis hostname | `redis` (Docker service name) |
| `QUEUE_BULL_REDIS_PORT` | Yes | Redis port | `6379` |
| **Security** | | | |
| `N8N_ENCRYPTION_KEY` | **CRITICAL** | Encryption key for credentials (64 hex chars) | Generate with `openssl rand -hex 32` |
| **Webhooks & Access** | | | |
| `N8N_HOST` | Yes | Domain or IP for n8n UI | `localhost` or `n8n.yourdomain.com` |
| `N8N_PROTOCOL` | Yes | Protocol (http or https) | `http` (use `https` with reverse proxy) |
| `WEBHOOK_URL` | Yes | Full webhook URL | `http://localhost:5678` |
| **Timezone** | | | |
| `GENERIC_TIMEZONE` | Yes | Timezone for scheduling | `America/New_York` |
| `TZ` | Yes | Container timezone (match GENERIC_TIMEZONE) | `America/New_York` |

### ⚠️ Critical Variables

**`N8N_ENCRYPTION_KEY`**: This key encrypts all credentials stored in the database. **If you lose this key, all saved credentials become permanently unrecoverable!**

- Generate: `openssl rand -hex 32`
- Store securely: password manager, encrypted backup, secrets vault
- **Never change** after initial setup
- **Never commit** to version control

---

## 🔒 Security Best Practices

### 1. Encryption Key Management
- ✅ Generate a strong encryption key (64 hex characters)
- ✅ Store encryption key in multiple secure locations (password manager + encrypted backup)
- ✅ Never change encryption key after initial setup
- ❌ Never commit encryption key to Git

### 2. Password Security
- ✅ Use strong, randomly generated passwords (see `scripts/generate-secrets.sh`)
- ✅ Different passwords for POSTGRES_PASSWORD and POSTGRES_NON_ROOT_PASSWORD
- ❌ Never use default or weak passwords in production

### 3. File Security
- ✅ `.env` file is gitignored (secrets not committed)
- ✅ SSH key permissions: `chmod 600 ~/.ssh/id_ed25519`
- ✅ Server file permissions: deployment scripts set proper permissions

### 4. Network Security
- ✅ PostgreSQL and Redis ports NOT exposed to host (internal Docker network only)
- ✅ Only port 5678 exposed for n8n UI
- ✅ Use reverse proxy (Nginx/Caddy) with TLS/SSL for HTTPS
- ✅ Configure firewall to allow only necessary ports

### 5. Production Hardening
- ✅ Use HTTPS in production (set `N8N_PROTOCOL=https` with reverse proxy)
- ✅ Enable n8n authentication (configured on first run)
- ✅ Regular backups: `bash scripts/backup-postgres.sh --retention-days 30`
- ✅ Monitor Docker logs: `docker compose logs -f`
- ✅ Keep Docker images updated: `docker compose pull && docker compose up -d`

---

## 📁 Project Structure

```
dash-n8n/
├── docker-compose.yml          # Docker Compose stack definition
├── .env.example                # Environment variable template
├── .env                        # Your actual secrets (gitignored)
├── .gitignore                  # Git ignore patterns
├── init-data.sh                # PostgreSQL initialization script
│
├── scripts/
│   ├── generate-secrets.sh     # Generate encryption key and passwords
│   ├── deploy-windows.ps1      # Windows deployment script
│   ├── deploy-linux.sh         # Linux/macOS deployment script
│   └── backup-postgres.sh      # PostgreSQL backup script
│
└── docs/
    ├── README.md               # This file - project overview
    ├── DEPLOYMENT.md           # Detailed deployment guide
    └── TROUBLESHOOTING.md      # Common issues and solutions
```

---

## 📚 Documentation

- **[Deployment Guide](./DEPLOYMENT.md)** - Step-by-step deployment instructions for Windows and Linux
- **[Troubleshooting Guide](./TROUBLESHOOTING.md)** - Common issues, diagnostic commands, backup/restore procedures
- **[Official n8n Documentation](https://docs.n8n.io/)** - n8n features, nodes, and workflows
- **[n8n Community Forum](https://community.n8n.io/)** - Get help from the n8n community

---

## 🔄 Common Operations

### Update n8n Version
```bash
# SSH to server
ssh user@your-server.com

# Navigate to deployment directory
cd /opt/n8n

# Pull new images and restart
docker compose pull
docker compose up -d

# Verify health
docker compose ps
```

### Backup Database
```bash
# Run backup script (on server)
bash scripts/backup-postgres.sh --retention-days 30

# Backups saved to: backups/n8n_backup_YYYYMMDD_HHMMSS.sql
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f n8n
docker compose logs -f postgres
```

### Restart Services
```bash
# Restart all
docker compose restart

# Restart specific service
docker compose restart n8n
```

---

## 🤝 Support

- **Issues**: If you encounter problems, check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- **n8n Documentation**: https://docs.n8n.io/
- **n8n Community**: https://community.n8n.io/
- **Docker Documentation**: https://docs.docker.com/

---

## 📄 License

This project is provided as-is for self-hosting n8n. Please refer to [n8n's license](https://github.com/n8n-io/n8n/blob/master/LICENSE.md) for n8n itself.

---

**Happy Automating! 🚀**
