param(
    [string]$CoordinatorUrl,
    [string]$AgentSecret,
    [string]$WorkerName = $env:COMPUTERNAME
)

# Helper function to write UTF-8 files without BOM (required for XMRig JSON parser)
function Write-ContentNoBom ($path, $content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}


# 1. Validate Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as an Administrator. Please restart PowerShell as Administrator."
    Exit 1
}

# 2. Prompt for parameters if not provided
if (-not $CoordinatorUrl) {
    $CoordinatorUrl = Read-Host "Enter Coordinator URL (e.g. http://localhost:3000)"
}
if (-not $AgentSecret) {
    $AgentSecret = Read-Host "Enter Agent Secret"
}

# Clean inputs
$CoordinatorUrl = $CoordinatorUrl.Trim().TrimEnd('/')
$AgentSecret = $AgentSecret.Trim()
$WorkerName = $WorkerName.Trim()

Write-Host "Installing Windows Agent for Distributed Miner..."
Write-Host "Coordinator: $CoordinatorUrl"
Write-Host "Worker Name: $WorkerName"

# 3. Create target directory structure
$InstallDir = "C:\ProgramData\xmrig-agent"
$LogsDir = Join-Path $InstallDir "logs"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

# Configure security protocol for TLS 1.2/1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 4. Download XMRig
$XmrigZip = Join-Path $env:TEMP "xmrig.zip"
$XmrigUrl = "https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-msvc-win64.zip"

Write-Host "Downloading XMRig from $XmrigUrl..."
try {
    Invoke-WebRequest -Uri $XmrigUrl -OutFile $XmrigZip -UseBasicParsing
} catch {
    Write-Error "Failed to download XMRig: $_"
    Exit 1
}

Write-Host "Extracting XMRig..."
$ExtractDir = Join-Path $env:TEMP "xmrig-extract"
try {
    if (Test-Path $ExtractDir) { Remove-Item -Path $ExtractDir -Recurse -Force | Out-Null }
    Expand-Archive -Path $XmrigZip -DestinationPath $ExtractDir -Force
    
    $XmrigExeSource = Get-ChildItem -Path $ExtractDir -Filter "xmrig.exe" -Recurse | Select-Object -First 1
    if (-not $XmrigExeSource) {
        Write-Error "xmrig.exe not found in extracted archive."
        Exit 1
    }
    
    Copy-Item -Path $XmrigExeSource.FullName -Destination (Join-Path $InstallDir "xmrig.exe") -Force
} catch {
    Write-Error "Failed to extract XMRig: $_"
    Exit 1
} finally {
    if (Test-Path $XmrigZip) { Remove-Item -Path $XmrigZip -Force }
    if (Test-Path $ExtractDir) { Remove-Item -Path $ExtractDir -Recurse -Force }
}

# 5. Download WinSW
$WinswPath = Join-Path $env:TEMP "WinSW-x64.exe"
$WinswUrl = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"

Write-Host "Downloading WinSW from $WinswUrl..."
try {
    Invoke-WebRequest -Uri $WinswUrl -OutFile $WinswPath -UseBasicParsing
    Copy-Item -Path $WinswPath -Destination (Join-Path $InstallDir "xmrig-service.exe") -Force
    Copy-Item -Path $WinswPath -Destination (Join-Path $InstallDir "xmrig-reporter-service.exe") -Force
} catch {
    Write-Error "Failed to download WinSW: $_"
    Exit 1
} finally {
    if (Test-Path $WinswPath) { Remove-Item -Path $WinswPath -Force }
}

# 6. Register device with coordinator
Write-Host "Registering device with coordinator..."
$RegisterUri = "$CoordinatorUrl/api/workers/register"
$Body = @{
    name = $WorkerName
    platform = "windows"
    ip = ""
} | ConvertTo-Json

$Headers = @{
    "X-Agent-Secret" = $AgentSecret
}

try {
    $Response = Invoke-RestMethod -Uri $RegisterUri -Method Post -Body $Body -ContentType "application/json" -Headers $Headers
    $WorkerId = $Response.id
    if (-not $WorkerId) {
        throw "No worker ID returned from coordinator"
    }
    Write-Host "Worker registered successfully. Worker ID: $WorkerId"
} catch {
    Write-Error "Registration failed: $_"
    Exit 1
}

# 7. Save agent credentials
$AgentConf = @{
    coordinator_url = $CoordinatorUrl
    agent_secret = $AgentSecret
    worker_id = [int]$WorkerId
} | ConvertTo-Json

Write-ContentNoBom (Join-Path $InstallDir "agent.conf") $AgentConf


# 8. Fetch mining config
Write-Host "Fetching mining configuration..."
$ConfigUri = "$CoordinatorUrl/api/config/mining"
try {
    $RemoteConfig = Invoke-RestMethod -Uri $ConfigUri -Method Get -Headers $Headers
    Write-Host "Config fetched: Pool = $($RemoteConfig.pool), Max CPU = $($RemoteConfig.cpu_max_percent)%"
} catch {
    Write-Warning "Failed to fetch mining config. Using default configuration."
    $RemoteConfig = @{
        pool = "pool.moneroocean.stream:10008"
        wallet = "YOUR_WALLET_ADDRESS"
        cpu_max_percent = 70
    }
}

# 9. Create config.json from template
$TemplatePath = Join-Path $PSScriptRoot "config-template.json"
if (-not (Test-Path $TemplatePath)) {
    # Try current directory as fallback
    $TemplatePath = Join-Path (Get-Location) "config-template.json"
}

if (-not (Test-Path $TemplatePath)) {
    Write-Error "config-template.json not found. Place it in the same directory as this script."
    Exit 1
}

try {
    $ConfigJson = Get-Content $TemplatePath -Raw | ConvertFrom-Json
    $ConfigJson.pools[0].url = $RemoteConfig.pool
    $ConfigJson.pools[0].user = $RemoteConfig.wallet
    $ConfigJson.pools[0]."rig-id" = $WorkerName
    $ConfigJson.cpu."max-threads-hint" = $RemoteConfig.cpu_max_percent
    
    Write-ContentNoBom (Join-Path $InstallDir "config.json") ($ConfigJson | ConvertTo-Json -Depth 10)
} catch {
    Write-Error "Failed to generate config.json: $_"
    Exit 1
}

# 10. Copy scripts and service configs
try {
    # Copy reporter script
    $ReporterSource = Join-Path $PSScriptRoot "reporter.ps1"
    if (-not (Test-Path $ReporterSource)) { $ReporterSource = Join-Path (Get-Location) "reporter.ps1" }
    Copy-Item -Path $ReporterSource -Destination (Join-Path $InstallDir "reporter.ps1") -Force
    
    # Copy template backup
    Copy-Item -Path $TemplatePath -Destination (Join-Path $InstallDir "config-template.json") -Force

    # Copy service XML configurations
    $XmlSource = Join-Path $PSScriptRoot "service-wrapper.xml"
    if (-not (Test-Path $XmlSource)) { $XmlSource = Join-Path (Get-Location) "service-wrapper.xml" }
    Copy-Item -Path $XmlSource -Destination (Join-Path $InstallDir "xmrig-service.xml") -Force

    $ReporterXmlSource = Join-Path $PSScriptRoot "reporter-service-wrapper.xml"
    if (-not (Test-Path $ReporterXmlSource)) { $ReporterXmlSource = Join-Path (Get-Location) "reporter-service-wrapper.xml" }
    Copy-Item -Path $ReporterXmlSource -Destination (Join-Path $InstallDir "xmrig-reporter-service.xml") -Force
} catch {
    Write-Error "Failed to copy configuration files: $_"
    Exit 1
}

# 11. Install and start services
Write-Host "Installing services..."
try {
    # Stop existing services if running
    if (Get-Service -Name "xmrig-miner" -ErrorAction SilentlyContinue) {
        Write-Host "Stopping existing xmrig-miner service..."
        Stop-Service -Name "xmrig-miner" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        # Uninstall
        Start-Process -FilePath (Join-Path $InstallDir "xmrig-service.exe") -ArgumentList "uninstall" -Wait -NoNewWindow
    }
    if (Get-Service -Name "xmrig-reporter" -ErrorAction SilentlyContinue) {
        Write-Host "Stopping existing xmrig-reporter service..."
        Stop-Service -Name "xmrig-reporter" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        # Uninstall
        Start-Process -FilePath (Join-Path $InstallDir "xmrig-reporter-service.exe") -ArgumentList "uninstall" -Wait -NoNewWindow
    }

    # Install miner service
    $InstallMinerProcess = Start-Process -FilePath (Join-Path $InstallDir "xmrig-service.exe") -ArgumentList "install" -Wait -NoNewWindow -PassThru
    if ($InstallMinerProcess.ExitCode -ne 0) {
        throw "Failed to install xmrig-miner service. Exit code: $($InstallMinerProcess.ExitCode)"
    }
    
    # Install reporter service
    $InstallReporterProcess = Start-Process -FilePath (Join-Path $InstallDir "xmrig-reporter-service.exe") -ArgumentList "install" -Wait -NoNewWindow -PassThru
    if ($InstallReporterProcess.ExitCode -ne 0) {
        throw "Failed to install xmrig-reporter service. Exit code: $($InstallReporterProcess.ExitCode)"
    }

    # Start services
    Write-Host "Starting services..."
    Start-Service -Name "xmrig-miner"
    Start-Service -Name "xmrig-reporter"
    
    Write-Host '✓ Installation completed successfully!'
    Write-Host ('Files located at: ' + $InstallDir)
    Write-Host 'Mining service (xmrig-miner) and Stats reporter (xmrig-reporter) are now running in the background.'
} catch {
    $ErrMsg = $_.Exception.Message
    Write-Error ('Failed to install or start services: ' + $ErrMsg)
    Exit 1
}
