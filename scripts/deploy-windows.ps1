<#
.SYNOPSIS
    Deploy n8n Docker Compose stack to remote server from Windows

.DESCRIPTION
    Uploads docker-compose.yml, .env, and init-data.sh to remote server,
    then deploys/updates the n8n stack using Docker Compose.
    Uses native Windows OpenSSH (ssh.exe/scp.exe).
    Optionally configures Nginx reverse proxy with SSL.

.PARAMETER Server
    Target server hostname or IP address (required)

.PARAMETER User
    SSH username for remote server (required)

.PARAMETER KeyPath
    Path to SSH private key (default: $env:USERPROFILE\.ssh\id_ed25519)

.PARAMETER RemotePath
    Remote deployment directory (default: /opt/n8n)

.PARAMETER Domain
    Domain name for Nginx configuration (optional)

.PARAMETER EnableSSL
    Enable SSL with Let's Encrypt (requires Domain and Email)

.PARAMETER Email
    Email for SSL certificate notifications (required with EnableSSL)

.PARAMETER DryRun
    Show commands without executing them

.EXAMPLE
    .\deploy-windows.ps1 -Server 192.168.1.100 -User ubuntu

.EXAMPLE
    .\deploy-windows.ps1 -Server my-server.com -User admin -KeyPath C:\keys\deploy.pem -DryRun

.EXAMPLE
    .\deploy-windows.ps1 -Server n8n.example.com -User deploy -Domain n8n.example.com -EnableSSL -Email admin@example.com

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Target server hostname or IP")]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [Parameter(Mandatory = $true, HelpMessage = "SSH username")]
    [ValidateNotNullOrEmpty()]
    [string]$User,

    [Parameter(Mandatory = $false)]
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",

    [Parameter(Mandatory = $false)]
    [string]$RemotePath = "/opt/n8n",

    [Parameter(Mandatory = $false)]
    [string]$Domain = "",

    [Parameter(Mandatory = $false)]
    [switch]$EnableSSL,

    [Parameter(Mandatory = $false)]
    [string]$Email = "",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Strict error handling
$ErrorActionPreference = "Stop"

# Helper functions for colored output
function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

# Execute command or show in dry-run mode
function Invoke-CommandOrDryRun {
    param(
        [string]$Command,
        [string]$Description
    )

    Write-Info $Description

    if ($DryRun) {
        Write-Warning-Custom "DRY-RUN: $Command"
        return $true
    }

    try {
        Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Command failed with exit code $LASTEXITCODE"
        }
        return $true
    }
    catch {
        Write-Error-Custom "Failed to execute: $Command"
        Write-Error-Custom $_.Exception.Message
        return $false
    }
}

# Main deployment script
try {
    Write-Info "=== n8n Windows Deployment Script ==="
    Write-Info "Target: $User@$Server"
    Write-Info "Remote Path: $RemotePath"
    Write-Info "SSH Key: $KeyPath"
    
    if ($Domain) {
        Write-Info "Domain: $Domain"
        Write-Info "SSL Enabled: $EnableSSL"
        if ($EnableSSL) {
            Write-Info "SSL Email: $Email"
        }
    }

    if ($DryRun) {
        Write-Warning-Custom "DRY-RUN MODE: No commands will be executed"
    }

    # Validate SSL parameters
    if ($EnableSSL) {
        if (-not $Domain) {
            Write-Error-Custom "-EnableSSL requires -Domain to be specified"
            exit 1
        }
        if (-not $Email) {
            Write-Error-Custom "-EnableSSL requires -Email to be specified for Let's Encrypt notifications"
            exit 1
        }
    }

    # Warn if domain specified without SSL
    if ($Domain -and -not $EnableSSL) {
        Write-Warning-Custom "Domain specified without -EnableSSL flag. Nginx will be configured for HTTP only."
        Write-Warning-Custom "For production use, add -EnableSSL flag to enable HTTPS."
    }

    # Validate prerequisites
    Write-Info "Validating prerequisites..."

    # Check SSH key exists
    if (-not (Test-Path $KeyPath)) {
        Write-Error-Custom "SSH key not found: $KeyPath"
        exit 1
    }

    # Check required files exist
    $requiredFiles = @(
        "docker-compose.yml",
        ".env",
        "init-data.sh"
    )

    # If domain is specified, add nginx scripts
    if ($Domain) {
        $requiredFiles += "scripts\setup-nginx.sh"
        if ($EnableSSL) {
            $requiredFiles += "scripts\setup-ssl.sh"
        }
        # Check if nginx directory exists
        if (Test-Path "nginx") {
            $nginxDir = $true
        }
    }

    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            Write-Error-Custom "Required file not found: $file"
            Write-Error-Custom "Ensure you run this script from the project root directory"
            exit 1
        }
    }

    # Check native OpenSSH is available
    $sshPath = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
    $scpPath = (Get-Command scp.exe -ErrorAction SilentlyContinue).Source

    if (-not $sshPath) {
        Write-Error-Custom "ssh.exe not found. Install native Windows OpenSSH."
        Write-Error-Custom "Run: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
        exit 1
    }

    if (-not $scpPath) {
        Write-Error-Custom "scp.exe not found. Install native Windows OpenSSH."
        Write-Error-Custom "Run: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
        exit 1
    }

    Write-Success "Prerequisites validated"

    # SSH connection options
    $sshOpts = "-i `"$KeyPath`" -o StrictHostKeyChecking=accept-new"
    $sshTarget = "$User@$Server"

    # Step 1: Create remote directory
    Write-Info "Step 1/5: Creating remote directory..."
    $cmd = "ssh.exe $sshOpts $sshTarget `"mkdir -p $RemotePath`""
    if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Creating $RemotePath on remote server")) {
        exit 1
    }
    Write-Success "Remote directory ready"

    # Step 2: Upload files
    Write-Info "Step 2/5: Uploading deployment files..."

    # Upload base files
    $baseFiles = @("docker-compose.yml", ".env", "init-data.sh")
    foreach ($file in $baseFiles) {
        $cmd = "scp.exe $sshOpts `"$file`" ${sshTarget}:$RemotePath/"
        if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Uploading $file")) {
            exit 1
        }
    }

    # Upload nginx directory if it exists and domain is specified
    if ($Domain -and (Test-Path "nginx")) {
        Write-Info "Uploading nginx configuration directory..."
        $cmd = "scp.exe -r $sshOpts `"nginx`" ${sshTarget}:$RemotePath/"
        if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Uploading nginx directory")) {
            exit 1
        }
    }

    # Upload scripts if domain is specified
    if ($Domain) {
        # Create scripts directory on remote
        $cmd = "ssh.exe $sshOpts $sshTarget `"mkdir -p $RemotePath/scripts`""
        Invoke-CommandOrDryRun -Command $cmd -Description "Creating scripts directory" | Out-Null

        $cmd = "scp.exe $sshOpts `"scripts\setup-nginx.sh`" ${sshTarget}:$RemotePath/scripts/"
        if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Uploading setup-nginx.sh")) {
            exit 1
        }

        if ($EnableSSL) {
            $cmd = "scp.exe $sshOpts `"scripts\setup-ssl.sh`" ${sshTarget}:$RemotePath/scripts/"
            if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Uploading setup-ssl.sh")) {
                exit 1
            }
        }
    }

    Write-Success "All files uploaded"

    # Step 3: Set permissions on init-data.sh
    Write-Info "Step 3/5: Setting file permissions..."
    $cmd = "ssh.exe $sshOpts $sshTarget `"chmod +x $RemotePath/init-data.sh`""
    if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Making init-data.sh executable")) {
        exit 1
    }
    Write-Success "Permissions set"

    # Step 4: Pull latest images
    Write-Info "Step 4/5: Pulling latest Docker images..."
    $cmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && docker compose pull`""
    if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Pulling Docker images")) {
        exit 1
    }
    Write-Success "Images pulled"

    # Step 5: Deploy stack
    Write-Info "Step 5/5: Deploying Docker Compose stack..."
    $cmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && docker compose up -d --remove-orphans`""
    if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Starting containers")) {
        exit 1
    }
    Write-Success "Stack deployed"

    # Step 6: Setup Nginx if domain is specified
    if ($Domain) {
        Write-Info "Step 6/7: Setting up Nginx reverse proxy..."

        # Make setup scripts executable
        $cmd = "ssh.exe $sshOpts $sshTarget `"chmod +x $RemotePath/scripts/setup-nginx.sh`""
        if ($EnableSSL) {
            $cmd += " && chmod +x $RemotePath/scripts/setup-ssl.sh"
        }
        Invoke-CommandOrDryRun -Command $cmd -Description "Making scripts executable" | Out-Null

        # Build nginx setup command
        $nginxCmd = "sudo ./scripts/setup-nginx.sh --domain $Domain --deployment-dir $RemotePath"
        if ($EnableSSL) {
            $nginxCmd += " --ssl --email $Email"
        }

        # Run nginx setup
        Write-Info "Configuring Nginx (this may take a few minutes)..."
        $cmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && $nginxCmd`""
        if (-not (Invoke-CommandOrDryRun -Command $cmd -Description "Configuring Nginx")) {
            Write-Error-Custom "Nginx setup failed"
            Write-Error-Custom "n8n services are running but not accessible via domain"
            Write-Error-Custom "Check logs on server: $RemotePath/scripts/setup-nginx.sh"
            exit 1
        }
        Write-Success "Nginx configured successfully"

        # Update .env with production URL if SSL is enabled
        if ($EnableSSL) {
            Write-Info "Step 7/7: Updating environment configuration..."
            $cmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && sed -i 's|^N8N_PROTOCOL=.*|N8N_PROTOCOL=https|' .env && sed -i 's|^N8N_HOST=.*|N8N_HOST=$Domain|' .env`""
            Invoke-CommandOrDryRun -Command $cmd -Description "Updating .env with HTTPS settings" | Out-Null

            # Restart n8n to apply new URL settings
            Write-Info "Restarting n8n services to apply configuration..."
            $cmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && docker compose restart n8n n8n-worker`""
            Invoke-CommandOrDryRun -Command $cmd -Description "Restarting services" | Out-Null

            if (-not $DryRun) {
                Start-Sleep -Seconds 10
            }
            Write-Success "Configuration updated"
        }
    }

    # Health check verification
    if (-not $DryRun) {
        Write-Info "Waiting 10 seconds for services to initialize..."
        Start-Sleep -Seconds 10

        Write-Info "Checking service health status..."
        $healthCmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && docker compose ps --format json`""

        try {
            $psOutput = Invoke-Expression $healthCmd
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
                Write-Warning-Custom "Could not retrieve container status"
            }
            else {
                Write-Info "Container Status:"
                # Parse JSON output and display status
                $cmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && docker compose ps`""
                Invoke-Expression $cmd

                # Check for healthy services
                Write-Info "`nChecking health status..."
                $healthyCmd = "ssh.exe $sshOpts $sshTarget `"cd $RemotePath && docker compose ps --format json | jq -r '.[] | select(.Health==\`"healthy\`") | .Service'`""

                try {
                    $healthyServices = Invoke-Expression $healthyCmd 2>$null
                    if ($healthyServices) {
                        Write-Success "Healthy services detected:"
                        $healthyServices -split "`n" | Where-Object { $_ -ne "" } | ForEach-Object {
                            Write-Host "  * $_" -ForegroundColor Green
                        }
                    }
                    else {
                        Write-Warning-Custom "No healthy services found yet (services may still be starting)"
                        Write-Info "Run 'docker compose ps' on the server to check status"
                    }
                }
                catch {
                    Write-Warning-Custom "Could not parse health status (jq may not be installed on remote)"
                }
            }
        }
        catch {
            Write-Warning-Custom "Could not retrieve container status"
        }
    }

    Write-Success "`n=== Deployment Complete ==="
    Write-Info "Services deployed to: ${Server}:${RemotePath}"
    
    if ($Domain) {
        if ($EnableSSL) {
            Write-Success "Access your n8n instance at: https://$Domain"
            Write-Info "SSL certificate automatically renews via certbot"
        } else {
            Write-Success "Access your n8n instance at: http://$Domain"
            Write-Warning-Custom "WARNING: HTTP only. For production, redeploy with -EnableSSL flag"
        }
    } else {
        Write-Info "n8n should be accessible at: http://${Server}:5678"
    }
    
    Write-Info "`nUseful commands:"
    Write-Info "  Check status: ssh $User@$Server 'cd $RemotePath && docker compose ps'"
    Write-Info "  View logs: ssh $User@$Server 'cd $RemotePath && docker compose logs -f'"
    Write-Info "  Restart: ssh $User@$Server 'cd $RemotePath && docker compose restart'"
    Write-Info "  Stop: ssh $User@$Server 'cd $RemotePath && docker compose down'"
    
    if ($Domain -and $EnableSSL) {
        Write-Info "`nSSL Management:"
        Write-Info "  Renew SSL: ssh $User@$Server 'sudo certbot renew'"
        Write-Info "  SSL status: ssh $User@$Server 'sudo certbot certificates'"
    }

    exit 0
}
catch {
    Write-Error-Custom "`n=== Deployment Failed ==="
    Write-Error-Custom $_.Exception.Message
    Write-Error-Custom $_.ScriptStackTrace
    exit 1
}
