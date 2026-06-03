# 1. Validate Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as an Administrator. Please restart PowerShell as Administrator."
    Exit 1
}

$InstallDir = "C:\ProgramData\xmrig-agent"

Write-Host "Uninstalling Windows Agent for Distributed Miner..."

# 2. Stop and uninstall reporter service
if (Get-Service -Name "xmrig-reporter" -ErrorAction SilentlyContinue) {
    Write-Host "Stopping xmrig-reporter service..."
    Stop-Service -Name "xmrig-reporter" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$ReporterServiceExe = Join-Path $InstallDir "xmrig-reporter-service.exe"
if (Test-Path $ReporterServiceExe) {
    Write-Host "Uninstalling xmrig-reporter service..."
    $Process = Start-Process -FilePath $ReporterServiceExe -ArgumentList "uninstall" -Wait -NoNewWindow -PassThru
    if ($Process.ExitCode -eq 0) {
        Write-Host "✓ xmrig-reporter service uninstalled successfully."
    } else {
        Write-Warning "Failed to uninstall xmrig-reporter service. Exit code: $($Process.ExitCode)"
    }
}

# 3. Stop and uninstall miner service
if (Get-Service -Name "xmrig-miner" -ErrorAction SilentlyContinue) {
    Write-Host "Stopping xmrig-miner service..."
    Stop-Service -Name "xmrig-miner" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$MinerServiceExe = Join-Path $InstallDir "xmrig-service.exe"
if (Test-Path $MinerServiceExe) {
    Write-Host "Uninstalling xmrig-miner service..."
    $Process = Start-Process -FilePath $MinerServiceExe -ArgumentList "uninstall" -Wait -NoNewWindow -PassThru
    if ($Process.ExitCode -eq 0) {
        Write-Host "✓ xmrig-miner service uninstalled successfully."
    } else {
        Write-Warning "Failed to uninstall xmrig-miner service. Exit code: $($Process.ExitCode)"
    }
}

# 4. Clean up files and directory
if (Test-Path $InstallDir) {
    Write-Host "Removing installation files from $InstallDir..."
    try {
        # Retry logic for locked files
        $RetryCount = 0
        $Success = $false
        while (-not $Success -and $RetryCount -lt 3) {
            try {
                Remove-Item -Path $InstallDir -Recurse -Force
                $Success = $true
            } catch {
                $RetryCount++
                Write-Warning "Files might be locked, retrying in 2 seconds..."
                Start-Sleep -Seconds 2
            }
        }
        if ($Success) {
            Write-Host "✓ All installation files removed successfully."
        } else {
            Write-Error "Failed to delete installation folder $InstallDir. Some files might still be in use."
        }
    } catch {
        Write-Error "Error cleaning up installation directory: $_"
    }
}

Write-Host "✓ Uninstallation completed!"
