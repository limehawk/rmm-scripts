<#
.SYNOPSIS
    Test script for validating superops-script-sync functionality.
.DESCRIPTION
    This script doesn't do anything meaningful - it exists solely to test
    the sync pipeline between GitHub and SuperOps RMM.
.NOTES
    Author: LimeHawk
    Created: 2026-03-14
#>

Write-Host "Sync test probe - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Hostname: $env:COMPUTERNAME"
Write-Host "OS: $([System.Environment]::OSVersion.VersionString)"
Write-Host "Test complete."
