#!/usr/bin/env pwsh

Write-Host "Updating System..." -ForegroundColor Green
Wevtutil cl System

Write-Host "Running Windows Update..." -ForegroundColor Green
SFC /scannow

Write-Host "Upgrading Chocolatey Packages..." -ForegroundColor Green
choco upgrade all -y

Write-Host "Upgrading Winget Packages..." -ForegroundColor Green
winget upgrade --all --accept-package-agreements --accept-source-agreements

Write-Host "Downloading and Installing Windows Updates..." -ForegroundColor Green
Get-WindowsUpdate -Download -Install -AcceptAll -Verbose -IgnoreReboot

Write-Host "Running Disk Cleanup..." -ForegroundColor Green
Cleanmgr /sagerun:999

Write-Host "Scanning for Malware with Windows Defender..." -ForegroundColor Green
# Set the path to the directory you want to search
$dirPath = "C:\ProgramData\Microsoft\Windows Defender\Platform"
# Get the last created subdirectory in the directory
$lastCreatedDir = Get-ChildItem -Path $dirPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1
# Enter the last created subdirectory
Set-Location $lastCreatedDir.FullName
.\MpCmdRun.exe -Scan -ScanType 2
cd "C:\users\zahrs"

Write-Host "Optimizing Drive Space..." -ForegroundColor Green
Defrag c: /u /v

Write-Host "Configuring TCP Settings..." -ForegroundColor Green
Netsh interface tcp set global autotuninglevel=normal

Write-Host "All Tasks Completed!" -ForegroundColor Green