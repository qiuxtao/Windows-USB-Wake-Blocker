# ==========================================
# WakeGuard - USB Wake Manager
# Description: Background service to automatically disable USB wake events (Mouse/Keyboard/Hubs)
# Author: [Your Name/GitHub]
# ==========================================
param(
    [string]$Action = "Info" 
)

$InstallDir = "C:\ProgramData\WakeGuard"
$ScriptPath = "$InstallDir\WakeGuard_Daemon.ps1"
$LogFile    = "$InstallDir\WakeGuard.log"
$TaskName   = "WakeGuard_Service"

# Check Administrator Privileges
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run as Administrator!"
    exit
}

# ==========================================
# Daemon Script Content
# ==========================================
$DaemonCode = @"
# --- WakeGuard Background Service ---
`$ErrorActionPreference = 'SilentlyContinue'
`$LogPath = "$LogFile"

# 1. WhiteList (Network/VM/Remote Access)
`$WhiteList = "Realtek|Intel.*Ethernet|Wi-Fi|WLAN|PCIe|Gaming.*Controller|网卡|以太网|ZeroTier|VMware|Virtual"

# 2. BlackList (Mouse/Keyboard/USB Controllers)
`$BlackList = "Mouse|Mice|Keyboard|Keypad|鼠标|键盘|Controller|Hub|集线器|控制器|Root"

function Write-Log {
    param(`$Msg)
    try {
        `$Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[`$Time] `$Msg" | Out-File -FilePath `$LogPath -Append -Encoding UTF8 -Force
    } catch {}
}

Write-Log "=== WakeGuard Service Started ==="

function Patrol-Round {
    try {
        `$ArmedDevices = cmd /c "powercfg /devicequery wake_armed"
        if (-not `$ArmedDevices) { return }

        foreach (`$dev in `$ArmedDevices) {
            `$dev = `$dev.Trim()
            if ([string]::IsNullOrWhiteSpace(`$dev)) { continue }

            if (`$dev -match `$BlackList -and `$dev -notmatch `$WhiteList) {
                
                # Native call to powercfg
                & powercfg /devicedisablewake "`$dev" 2>&1 | Out-Null
                
                if (`$LASTEXITCODE -eq 0) {
                    Write-Log "DISABLED: `$dev"
                } else {
                    Write-Log "WARNING: Failed to disable `$dev (ExitCode: `$LASTEXITCODE)"
                }
            }
        }
    } catch {
        Write-Log "ERROR: `$_\`$(`$Error[0].ScriptStackTrace)"
    }
}

# Main Loop (Interval: 5s)
while (`$true) {
    Patrol-Round
    Start-Sleep -Seconds 5
}
"@

# ==========================================
# Install / Uninstall Logic
# ==========================================

if ($Action -eq "Install") {
    Write-Host "Installing WakeGuard Service..." -ForegroundColor Cyan

    # Cleanup old instances
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $Procs = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match "WakeGuard_Daemon.ps1" }
    foreach ($p in $Procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }

    # Setup directories
    if (-not (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
    Set-Content -Path $ScriptPath -Value $DaemonCode -Encoding UTF8
    Write-Host " -> Script generated."

    # Register Task (Run as Current User)
    $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $ActionObj = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""
    $TriggerObj = New-ScheduledTaskTrigger -AtLogOn
    $SettingsObj = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -Hidden
    
    Register-ScheduledTask -TaskName $TaskName -Action $ActionObj -Trigger $TriggerObj -Settings $SettingsObj -User $CurrentUser -RunLevel Highest -Force | Out-Null
    
    # Start Task
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 2
    
    $TaskState = Get-ScheduledTask -TaskName $TaskName
    if ($TaskState.State -eq "Running") {
        Write-Host "✅ Installation Complete. Service is running." -ForegroundColor Green
        Write-Host " -> Log file: $LogFile" -ForegroundColor Gray
    } else {
        Write-Host "❌ Installation finished but task is not running." -ForegroundColor Red
    }

} elseif ($Action -eq "Uninstall") {
    Write-Host "Uninstalling WakeGuard..." -ForegroundColor Yellow
    
    # Remove Task and Process
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $Procs = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -match "WakeGuard_Daemon.ps1" }
    foreach ($p in $Procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    
    # Remove Files
    if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force }
    
    # Restore Functionality (Re-enable wake for Mouse/Keyboard)
    Write-Host "Restoring wake privileges for Keyboard/Mouse..."
    $RestorePattern = "Mouse|Mice|Keyboard|Keypad|鼠标|键盘"
    $IgnorePattern = "Realtek|Intel.*Ethernet|Wi-Fi|WLAN|PCIe|Gaming.*Controller|网卡|以太网"
    
    $AllDevices = (cmd /c "powercfg /devicequery wake_programmable") | Where-Object { $_ -match "\S" }
    foreach ($dev in $AllDevices) {
        $dev = $dev.Trim()
        if ($dev -match $RestorePattern -and $dev -notmatch $IgnorePattern) {
            cmd /c "powercfg /deviceenablewake `"$dev`""
            Write-Host " -> Restored: $dev" -ForegroundColor Gray
        }
    }
    Write-Host "✅ Uninstallation Complete." -ForegroundColor Green

} else {
    Write-Host "Usage: .\WakeGuard.ps1 -Action [Install|Uninstall]"
}