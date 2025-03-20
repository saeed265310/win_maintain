#!/usr/bin/env pwsh

# Display the current script location and prompt for confirmation
$currentScriptPath = $MyInvocation.MyCommand.Path
Write-Host "Current script location: $currentScriptPath" -ForegroundColor Cyan
Write-Host "Is this location acceptable? (Y/N). Default is 'Y' after 15 seconds..." -ForegroundColor Yellow

$response = $null
$timer = 15
While ($timer -gt 0 -and -not $Host.UI.RawUI.KeyAvailable) {
    Start-Sleep -Seconds 1
    $timer--
}
if ($Host.UI.RawUI.KeyAvailable) {
    $response = [string]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToUpper()
}

if ($response -eq "N") {
    Write-Host "Enter a new folder path for logs and the script:" -ForegroundColor Cyan
    $folderPath = Read-Host "Folder Path"
    if (-not (Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath | Out-Null
    }
    $scriptName = Split-Path -Path $currentScriptPath -Leaf
    $currentScriptPath = Join-Path -Path $folderPath -ChildPath $scriptName
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $currentScriptPath -Force
} elseif ($response -ne "Y" -and $response -ne "") {
    Write-Host "Invalid input. Defaulting to Yes." -ForegroundColor Yellow
}

# Determine log file location
$folderPath = Split-Path -Path $currentScriptPath -Parent
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path -Path $folderPath -ChildPath "DailyUpdate_$timestamp.txt"

# Scheduled Task Handling
$taskName = "WindowsDailyMaintenance"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Scheduled task found. Updating the script path in the schedule..." -ForegroundColor Yellow
    $newAction = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$currentScriptPath`""
    Set-ScheduledTask -TaskName $taskName -Action $newAction
    Write-Host "Scheduled task updated successfully with the new script location." -ForegroundColor Green
} else {
    Write-Host "No existing scheduled task found. Creating a new task..." -ForegroundColor Yellow

    # Prompt the user for scheduling details
    Write-Host "Enter the time you want the script to run daily (e.g., 10:00AM):" -ForegroundColor Cyan
    $time = Read-Host "Time"

    # Create a new scheduled task
    $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$currentScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $time
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName $taskName -Description "Daily maintenance script"
    Write-Host "Scheduled task created successfully at $time daily." -ForegroundColor Green
}

# Log function
function Log-Result {
    param ([string]$message)
    Add-Content -Path $logFile -Value $message
}

# Maintenance Tasks
Wevtutil cl System
Log-Result "System Logs cleared successfully."

SFC /scannow
Log-Result "SFC scan completed successfully."

choco upgrade all -y
winget upgrade --all --accept-package-agreements --accept-source-agreements
Log-Result "Chocolatey and Winget packages updated."

Test-Connection -ComputerName 8.8.8.8 -Count 2 | ForEach-Object {
    Log-Result "Ping: $_"
}

New-BurntToastNotification -Text "Daily Maintenance", "Completed successfully!"
