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
    
    try {
        Add-Content -Path $LogFile -Value $LogLine -ErrorAction SilentlyContinue
    } catch {}
}

Log-Message "Starting XMRig Stats Reporter..."

# 1. Read agent.conf to get COORDINATOR_URL, AGENT_SECRET, WORKER_ID
if (-not (Test-Path $ConfigFile)) {
    Log-Message "Error: agent.conf not found at $ConfigFile. Exiting."
    Exit 1
}

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

# 2. Fetch startup config from coordinator (source of truth — do NOT read config.json)
$lastPool = $null
$lastWallet = $null
$lastCpu = $null

try {
    $StartupHeaders = @{ "X-Agent-Secret" = $AgentSecret }
    $StartupConfigUri = "$CoordinatorUrl/api/config"
    $StartupConfig = Invoke-RestMethod -Uri $StartupConfigUri -Method Get -Headers $StartupHeaders -TimeoutSec 10
    if ($StartupConfig -and $StartupConfig.pool) {
        $lastPool   = [string]$StartupConfig.pool
        $lastWallet = [string]$StartupConfig.wallet
        $lastCpu    = [string]$StartupConfig.cpu_max_percent
        Log-Message "Loaded startup config from coordinator: pool='$lastPool', wallet='$lastWallet', cpu='$lastCpu'"
    } else {
        Log-Message "Warning: Coordinator returned empty config at startup. Will initialise on first cycle."
    }
} catch {
    Log-Message "Warning: Failed to fetch startup config from coordinator: $_. Will initialise on first cycle."
}

# 3. Main loop (repeat forever)
while ($true) {
    # a. Fetch http://localhost:3333/1/summary
    $Hashrate = 0.0
    $Uptime = 0
    try {
        $Response = Invoke-RestMethod -Uri "http://localhost:3333/1/summary" -Method Get -TimeoutSec 5
        if ($Response) {
            $Hashrate = $Response.hashrate.total[0]
            if ($Hashrate -eq $null) { $Hashrate = 0.0 }
            $Uptime = $Response.connection.uptime
            if ($Uptime -eq $null) { $Uptime = 0 }
        }
    } catch {
        $Hashrate = 0.0
        $Uptime = 0
    }

    # b. Get CPU usage via Get-Counter
    $CpuPercent = 0.0
    try {
        $Counter = Get-Counter -Counter "\Processor(_Total)\% Processor Time" -MaxSamples 1 -ErrorAction Stop
        $CpuPercent = $Counter.CounterSamples[0].CookedValue
        if ($CpuPercent -eq $null) { $CpuPercent = 0.0 }
    } catch {
        try {
            $CpuInfo = Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average
            $CpuPercent = $CpuInfo.Average
            if ($CpuPercent -eq $null) { $CpuPercent = 0.0 }
        } catch {
            $CpuPercent = 0.0
        }
    }

    # c. POST /api/stats to coordinator with X-Agent-Secret header
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

        $StatsUri = "$CoordinatorUrl/api/stats"
        $PostResponse = Invoke-RestMethod -Uri $StatsUri -Method Post -Body $StatsBody -ContentType "application/json" -Headers $Headers -TimeoutSec 10
        Log-Message "Stats reported successfully (hashrate=$Hashrate H/s, cpu=$([math]::Round($CpuPercent,1))%)"
    } catch {
        Log-Message "Error: Failed to POST stats to coordinator: $_"
    }

    # d. Fetch GET /api/config from coordinator
    $newPool = $null
    $newWallet = $null
    $newCpu = $null
    try {
        $Headers = @{
            "X-Agent-Secret" = $AgentSecret
        }
        $ConfigUri = "$CoordinatorUrl/api/config"
        $RemoteConfig = Invoke-RestMethod -Uri $ConfigUri -Method Get -Headers $Headers -TimeoutSec 10
        if ($RemoteConfig -and $RemoteConfig.pool) {
            $newPool   = [string]$RemoteConfig.pool
            $newWallet = [string]$RemoteConfig.wallet
            $newCpu    = [string]$RemoteConfig.cpu_max_percent
        }
    } catch {
        Log-Message "Warning: Failed to fetch config from coordinator: $_"
    }

    # e. Compare
    if ($null -ne $newPool) {
        if ($newPool -ne $lastPool -or 
            $newWallet -ne $lastWallet -or 
            $newCpu -ne $lastCpu) {
            
            Log-Message "Config changed, restarting XMRig"

            # Load template (preferred) or fall back to current config
            if (Test-Path $TemplateFile) {
                $Template = Get-Content $TemplateFile -Raw | ConvertFrom-Json
            } elseif (Test-Path $XmrigConfigFile) {
                $Template = Get-Content $XmrigConfigFile -Raw | ConvertFrom-Json
            } else {
                Log-Message "Error: neither config-template.json nor config.json found. Skipping update."
                throw "No config template available"
            }

            # Preserve rig-id from existing config if present
            $RigId = $null
            if (Test-Path $XmrigConfigFile) {
                try {
                    $Existing = Get-Content $XmrigConfigFile -Raw | ConvertFrom-Json
                    $RigId = $Existing.pools[0]."rig-id"
                } catch { }
            }

            # Apply new settings
            $Template.pools[0].url  = $newPool
            $Template.pools[0].user = $newWallet
            $Template.pools[0].pass = "x"
            if ($RigId) { $Template.pools[0]."rig-id" = $RigId }
            $Template.cpu."max-threads-hint" = [int]$newCpu
            $Template.autosave = $false # Force autosave false to prevent XMRig from stripping max-threads-hint

            Write-ContentNoBom $XmrigConfigFile ($Template | ConvertTo-Json -Depth 10)

            # Restart xmrig-service (try xmrig-service, fall back to xmrig-miner)
            try {
                if (Get-Service -Name "xmrig-service" -ErrorAction SilentlyContinue) {
                    Restart-Service -Name "xmrig-service" -Force
                } else {
                    Restart-Service -Name "xmrig-miner" -Force
                }
            } catch {
                Log-Message "Error restarting service: $_"
            }

            # Update $lastPool, $lastWallet, $lastCpu
            $lastPool = $newPool
            $lastWallet = $newWallet
            $lastCpu = $newCpu
        } else {
            Log-Message "Config unchanged, no restart needed"
        }
    }

    # f. Sleep 60 seconds
    Start-Sleep -Seconds 60
}
