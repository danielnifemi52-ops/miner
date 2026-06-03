$ConfigFile = Join-Path $PSScriptRoot "agent.conf"
$XmrigConfigFile = Join-Path $PSScriptRoot "config.json"
$TemplateFile = Join-Path $PSScriptRoot "config-template.json"
$LogFile = Join-Path $PSScriptRoot "logs\reporter.log"

# Helper function to write UTF-8 files without BOM (required for XMRig JSON parser)
function Write-ContentNoBom ($path, $content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}


function Log-Message {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$Timestamp] $Message"
    Write-Output $LogLine
    
    # Ensure logs directory exists
    $LogDir = Split-Path $LogFile
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    Add-Content -Path $LogFile -Value $LogLine
}

Log-Message "Starting XMRig Stats Reporter..."

if (-not (Test-Path $ConfigFile)) {
    Log-Message "Error: agent.conf not found at $ConfigFile. Exiting."
    Exit 1
}

# Load agent config
try {
    $AgentConf = Get-Content $ConfigFile -Raw | ConvertFrom-Json
} catch {
    Log-Message "Error parsing agent.conf: $_. Exiting."
    Exit 1
}

$CoordinatorUrl = $AgentConf.coordinator_url
$AgentSecret = $AgentConf.agent_secret
$WorkerId = $AgentConf.worker_id

if (-not $CoordinatorUrl -or -not $AgentSecret -or -not $WorkerId) {
    Log-Message "Error: invalid configuration in agent.conf. Exiting."
    Exit 1
}

Log-Message "Coordinator: $CoordinatorUrl"
Log-Message "Worker ID: $WorkerId"

# Configure security protocol for TLS 1.2/1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$LoopCount = 0
while ($true) {
    # Get stats from XMRig HTTP API
    $Hashrate = 0.0
    $Uptime = 0
    
    try {
        $Response = Invoke-RestMethod -Uri "http://127.0.0.1:18081/1/summary" -Method Get -TimeoutSec 5
        if ($Response) {
            $Hashrate = $Response.hashrate.total[0]
            if ($Hashrate -eq $null) { $Hashrate = 0.0 }
            $Uptime = $Response.connection.uptime
            if ($Uptime -eq $null) { $Uptime = 0 }
        }
    } catch {
        # XMRig API might be down / not started yet
        Log-Message "Warning: Failed to connect to XMRig HTTP API. Miner might be starting or stopped."
    }

    # Get system CPU load percentage
    $CpuPercent = 0.0
    try {
        $CpuInfo = Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average
        $CpuPercent = $CpuInfo.Average
        if ($CpuPercent -eq $null) { $CpuPercent = 0.0 }
    } catch {
        Log-Message "Warning: Failed to get CPU load percentage: $_"
    }

    # Send stats to coordinator
    try {
        $StatsBody = @{
            worker_id = [int]$WorkerId
            hashrate = [double]$Hashrate
            cpu_percent = [double]$CpuPercent
            uptime_secs = [int]$Uptime
        } | ConvertTo-Json

        $Headers = @{
            "X-Agent-Secret" = $AgentSecret
        }

        $StatsUri = "$CoordinatorUrl/api/workers/stats"
        $PostResponse = Invoke-RestMethod -Uri $StatsUri -Method Post -Body $StatsBody -ContentType "application/json" -Headers $Headers -TimeoutSec 10
        if ($PostResponse -and $PostResponse.success) {
            # Log periodic status (every 5 loops / 5 minutes)
            if ($LoopCount % 5 -eq 0) {
                Log-Message "Stats reported successfully. Hashrate: $Hashrate H/s, CPU: $CpuPercent%, Uptime: $Uptime s"
            }
        } else {
            Log-Message "Warning: Coordinator rejected stats: $PostResponse"
        }
    } catch {
        Log-Message "Error reporting stats to coordinator: $_"
    }

    # Periodic config sync (every 5 minutes / 5 loops of 60 seconds)
    if ($LoopCount % 5 -eq 0 -and $LoopCount -gt 0) {
        try {
            $Headers = @{ "X-Agent-Secret" = $AgentSecret }
            $ConfigUri = "$CoordinatorUrl/api/config/mining"
            $RemoteConfig = Invoke-RestMethod -Uri $ConfigUri -Method Get -Headers $Headers -TimeoutSec 10
            
            if ($RemoteConfig -and $RemoteConfig.pool) {
                # Load current local config
                if (Test-Path $XmrigConfigFile) {
                    $LocalConfig = Get-Content $XmrigConfigFile -Raw | ConvertFrom-Json
                    
                    # Check if config differs
                    $ConfigChanged = $false
                    
                    # Check pool
                    if ($LocalConfig.pools[0].url -ne $RemoteConfig.pool) { $ConfigChanged = $true }
                    # Check wallet
                    if ($LocalConfig.pools[0].user -ne $RemoteConfig.wallet) { $ConfigChanged = $true }
                    # Check cpu limit
                    if ($LocalConfig.cpu."max-threads-hint" -ne $RemoteConfig.cpu_max_percent) { $ConfigChanged = $true }

                    if ($ConfigChanged) {
                        Log-Message "Configuration change detected from coordinator. Updating local configuration..."
                        
                        # Load template
                        if (Test-Path $TemplateFile) {
                            $Template = Get-Content $TemplateFile -Raw | ConvertFrom-Json
                        } else {
                            $Template = $LocalConfig
                        }
                        
                        # Apply new settings
                        $Template.pools[0].url = $RemoteConfig.pool
                        $Template.pools[0].user = $RemoteConfig.wallet
                        $Template.pools[0].pass = "x"
                        $Template.pools[0]."rig-id" = $LocalConfig.pools[0]."rig-id" # Preserve worker name
                        $Template.cpu."max-threads-hint" = $RemoteConfig.cpu_max_percent
                        
                        Write-ContentNoBom $XmrigConfigFile ($Template | ConvertTo-Json -Depth 10)
                        
                        Log-Message "Restarting XMRig Mining Service to apply changes..."
                        Restart-Service -Name "xmrig-miner" -Force
                        Log-Message "XMRig service restarted successfully."
                    }
                }
            }
        } catch {
            Log-Message "Warning: Failed to sync configuration with coordinator: $_"
        }
    }

    $LoopCount++
    Start-Sleep -Seconds 60
}
