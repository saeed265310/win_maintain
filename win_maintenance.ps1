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
$logFile = Join-Path -Path $folderPath -ChildPath "WeeklyUpdate_$timestamp.txt"

# Scheduled Task Handling
$taskName = "WindowsWeeklyMaintenance"
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Scheduled task found. Updating the script path in the schedule..." -ForegroundColor Yellow
    $newAction = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$currentScriptPath`""
    Set-ScheduledTask -TaskName $taskName -Action $newAction
    Write-Host "Scheduled task updated successfully with the new script location." -ForegroundColor Green
} else {
    Write-Host "No existing scheduled task found. Creating a new task..." -ForegroundColor Yellow

    # Prompt the user for scheduling details
    Write-Host "Enter the time you want the script to run weekly (e.g., 10:00AM):" -ForegroundColor Cyan
    $time = Read-Host "Time"
    Write-Host "Enter the day of the week (e.g., Sunday):" -ForegroundColor Cyan
    $day = Read-Host "Day"

    # Create a new scheduled task
    $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File `"$currentScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $day.Trim() -At $time
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName $taskName -Description "Weekly maintenance script"
    Write-Host "Scheduled task created successfully for $day at $time." -ForegroundColor Green
}

# Log function
function Log-Result {
    param ([string]$message)
    Add-Content -Path $logFile -Value $message
}

# Perform Daily Maintenance Tasks
Write-Host "Performing daily maintenance tasks..." -ForegroundColor Green

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

# Perform Weekly Maintenance Tasks
Write-Host "Performing weekly maintenance tasks..." -ForegroundColor Green

Write-Host "Running Disk Cleanup..." -ForegroundColor Green
Cleanmgr /sagerun:999
Log-Result "Disk cleanup completed."

Write-Host "Checking Disk Health on All Drives..." -ForegroundColor Green
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $driveLetter = $_.Name + ":"
    $chkdskResult = chkdsk $driveLetter /scan
    Log-Result "Disk health checked on drive $driveLetter: $chkdskResult"
}

Write-Host "Optimizing Drives..." -ForegroundColor Green
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $driveLetter = $_.Name + ":"
    $defragResult = defrag $driveLetter /u /v
    Log-Result "Drive optimization completed on drive $driveLetter: $defragResult"
}

Write-Host "Running Malware Scan..." -ForegroundColor Green
$defenderPath = "C:\ProgramData\Microsoft\Windows Defender\Platform"
$latestPath = (Get-ChildItem -Path $defenderPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName
Set-Location $latestPath
.\MpCmdRun.exe -Scan -ScanType 2
cd "C:\"
Log-Result "Malware scan completed."

Write-Host "Reviewing System Logs for Errors..." -ForegroundColor Green
Get-EventLog -LogName System -EntryType Error, Warning -Newest 50 | ForEach-Object {
    Log-Result "Log Error/Warning: $($_.Message)"
}

Write-Host "Archiving Log Files..." -ForegroundColor Green
Get-ChildItem -Path $folderPath -Filter "*.txt" | Where-Object {
    $_.LastWriteTime -lt (Get-Date).AddDays(-30)
} | Move-Item -Destination (Join-Path -Path $folderPath -ChildPath "Archive")
Log-Result "Old log files archived successfully."

Write-Host "Configuring Network TCP Settings..." -ForegroundColor Green
Netsh interface tcp set global autotuninglevel=normal
Log-Result "TCP settings adjusted."

# Finalize Script
New-BurntToastNotification -Text "Weekly Maintenance", "Script completed successfully!"
Write-Host "Weekly maintenance completed. Check the log file at $logFile for details." -ForegroundColor Green
