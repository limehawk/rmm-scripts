$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Workstation Reboot Schedule                                   v1.0.0
 AUTHOR   : Limehawk.io
 DATE     : September 2026
 USAGE    : .\workstation_reboot_schedule.ps1
================================================================================
 FILE     : workstation_reboot_schedule.ps1
 DESCRIPTION : Schedules a one-time 3:00 AM local reboot on a workstation and removes the scheduled task after it expires
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Schedules a single workstation reboot for the next 3:00 AM local time when
   uptime is over the threshold. Task Scheduler deletes the task after its
   window ends, so a missed night leaves nothing behind.

 DATA SOURCES & PRIORITY

   - Hardcoded settings in this script
   - Win32_OperatingSystem for product type and last boot time
   - Task Scheduler for an existing task of the same name

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $UptimeThresholdDays: Whole days of uptime required before a reboot
       is scheduled. Integer, 1 or greater. Default: 30
     - $RebootHour: Local hour for the one-time reboot, 0 through 23.
       Default: 3
     - $RebootMinute: Local minute for the one-time reboot, 0 through 59.
       Default: 0
     - $TaskName: Scheduled task name. Non-empty. Default:
       Limehawk-UptimeReboot
     - $TaskWindowMinutes: Minutes after the start time before the task
       expires and Task Scheduler deletes it. Integer, 1 or greater.
       Default: 15

 SETTINGS

   - Reboot time: next 03:00 local, or the following day if that time has
     already passed
   - Task name: Limehawk-UptimeReboot
   - Window: 15 minutes, then the task expires and is deleted
   - StartWhenAvailable: off, so a machine that was off at 3:00 AM does not
     reboot when someone opens it later
   - Batteries: the task may start on battery
   - Account: SYSTEM, highest privileges
   - Shutdown: shutdown.exe /r /t 0 /f

 BEHAVIOR

   The script performs the following actions in order:
   1. Validates the hardcoded settings
   2. Exits successfully on a server or domain controller
   3. Exits successfully when uptime is at or under the threshold
   4. Exits successfully when the scheduled task already exists
   5. Registers a one-time task for the next reboot time
   6. Leaves removal of that task to Task Scheduler after the window ends

 PREREQUISITES

   - PowerShell 5.1 or later
   - Windows workstation (ProductType 1)
   - Administrator privileges, so the task can be registered as SYSTEM

 SECURITY NOTES

   - No secrets in logs
   - The reboot closes applications without a prompt at the scheduled time
   - The task runs as SYSTEM and is deleted by Task Scheduler after it expires

 ENDPOINTS

   - Not applicable. This script performs local actions only.

 EXIT CODES

   0 = Success (reboot scheduled, already scheduled, or not needed)
   1 = Failure (input validation failed or the task could not be registered)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Uptime Threshold Days : 30
   Reboot Time : 03:00
   Task Name : Limehawk-UptimeReboot
   Task Window Minutes : 15

   [INFO] DEVICE CHECK
   ==============================================================
   Product Type : Workstation

   [INFO] UPTIME CHECK
   ==============================================================
   Last Boot : 2026-08-01T09:12:00
   Uptime Days : 52
   Threshold Days : 30
   Uptime Exceeded : Yes

   [RUN] SCHEDULE REBOOT
   ==============================================================
   Reboot At : 2026-09-23T03:00:00
   Expires At : 2026-09-23T03:15:00
   Task : Registered

   [OK] FINAL STATUS
   ==============================================================
   Reboot scheduled

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-09-22 v1.0.0 Initial release
================================================================================
#>

# ==== HARDCODED INPUTS ====
$UptimeThresholdDays = 30
$RebootHour          = 3
$RebootMinute        = 0
$TaskName            = 'Limehawk-UptimeReboot'
$TaskWindowMinutes   = 15

Set-StrictMode -Version Latest

function Write-Section {
    param([string]$Type, [string]$Name)
    $indicators = @{ 'info' = 'INFO'; 'run' = 'RUN'; 'ok' = 'OK'; 'warn' = 'WARN'; 'error' = 'ERROR' }
    $label = $indicators[$Type]
    Write-Host ''
    Write-Host "[$label] $Name"
    Write-Host ('=' * 62)
}

function Write-KV {
    param([string]$Label, [string]$Value)
    Write-Host ("{0} : {1}" -f $Label, $Value)
}

$errorOccurred = $false
$errorText = ''

if ($UptimeThresholdDays -lt 1) {
    $errorOccurred = $true
    $errorText += "- Uptime threshold must be an integer of 1 or greater`n"
}
if ($RebootHour -lt 0 -or $RebootHour -gt 23) {
    $errorOccurred = $true
    $errorText += "- Reboot hour must be from 0 through 23`n"
}
if ($RebootMinute -lt 0 -or $RebootMinute -gt 59) {
    $errorOccurred = $true
    $errorText += "- Reboot minute must be from 0 through 59`n"
}
if ([string]::IsNullOrWhiteSpace($TaskName)) {
    $errorOccurred = $true
    $errorText += "- Task name is required`n"
}
if ($TaskWindowMinutes -lt 1) {
    $errorOccurred = $true
    $errorText += "- Task window must be an integer of 1 or greater`n"
}

if ($errorOccurred) {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-Host $errorText.TrimEnd()
    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host 'Input validation failed'
    Write-Section -Type 'error' -Name 'SCRIPT COMPLETED'
    exit 1
}

$rebootTimeText = '{0:D2}:{1:D2}' -f $RebootHour, $RebootMinute

Write-Section -Type 'info' -Name 'INPUT VALIDATION'
Write-KV -Label 'Uptime Threshold Days' -Value ([string]$UptimeThresholdDays)
Write-KV -Label 'Reboot Time' -Value $rebootTimeText
Write-KV -Label 'Task Name' -Value $TaskName
Write-KV -Label 'Task Window Minutes' -Value ([string]$TaskWindowMinutes)

try {
    Write-Section -Type 'info' -Name 'DEVICE CHECK'

    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    $productType = [int]$operatingSystem.ProductType
    $productLabel = switch ($productType) {
        1 { 'Workstation' }
        2 { 'Domain Controller' }
        3 { 'Server' }
        default { 'Unknown' }
    }
    Write-KV -Label 'Product Type' -Value $productLabel

    if ($productType -ne 1) {
        Write-Section -Type 'ok' -Name 'FINAL STATUS'
        Write-Host 'No reboot scheduled. This computer is not a workstation.'
        Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'
        exit 0
    }

    Write-Section -Type 'info' -Name 'UPTIME CHECK'

    $bootTime = [datetime]$operatingSystem.LastBootUpTime
    $uptimeDays = [int][math]::Floor(((Get-Date) - $bootTime).TotalDays)
    $uptimeExceeded = $uptimeDays -gt $UptimeThresholdDays

    Write-KV -Label 'Last Boot' -Value $bootTime.ToString('yyyy-MM-ddTHH:mm:ss')
    Write-KV -Label 'Uptime Days' -Value ([string]$uptimeDays)
    Write-KV -Label 'Threshold Days' -Value ([string]$UptimeThresholdDays)
    Write-KV -Label 'Uptime Exceeded' -Value $(if ($uptimeExceeded) { 'Yes' } else { 'No' })

    if (-not $uptimeExceeded) {
        Write-Section -Type 'ok' -Name 'FINAL STATUS'
        Write-Host 'No reboot scheduled. Uptime is within the threshold.'
        Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'
        exit 0
    }

    Write-Section -Type 'run' -Name 'SCHEDULE REBOOT'

    $taskExists = $false
    try {
        $null = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $taskExists = $true
    }
    catch {
        $notFound = $_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound
        if (-not $notFound) {
            throw
        }
    }

    if ($taskExists) {
        Write-KV -Label 'Task' -Value 'Already registered'
        Write-Section -Type 'ok' -Name 'FINAL STATUS'
        Write-Host 'No change. A reboot task is already waiting.'
        Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'
        exit 0
    }

    $now = Get-Date
    $rebootAt = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $RebootHour -Minute $RebootMinute -Second 0
    if ($rebootAt -le $now) {
        $rebootAt = $rebootAt.AddDays(1)
    }
    $expiresAt = $rebootAt.AddMinutes($TaskWindowMinutes)

    $shutdownExe = Join-Path $env:SystemRoot 'System32\shutdown.exe'
    $action = New-ScheduledTaskAction -Execute $shutdownExe -Argument '/r /t 0 /f /d p:4:1 /c "Scheduled maintenance reboot"'
    $trigger = New-ScheduledTaskTrigger -Once -At $rebootAt
    $trigger.EndBoundary = $expiresAt.ToString('yyyy-MM-ddTHH:mm:ss')
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    $null = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'One-time maintenance reboot. Task Scheduler deletes this task after it expires.'

    Write-KV -Label 'Reboot At' -Value $rebootAt.ToString('yyyy-MM-ddTHH:mm:ss')
    Write-KV -Label 'Expires At' -Value $expiresAt.ToString('yyyy-MM-ddTHH:mm:ss')
    Write-KV -Label 'Task' -Value 'Registered'

    Write-Section -Type 'ok' -Name 'FINAL STATUS'
    Write-Host 'Reboot scheduled'
    Write-Section -Type 'ok' -Name 'SCRIPT COMPLETED'
    exit 0
}
catch {
    Write-Section -Type 'error' -Name 'ERROR OCCURRED'
    Write-KV -Label 'Step' -Value 'Schedule reboot'
    Write-KV -Label 'Error Type' -Value $_.Exception.GetType().Name
    Write-KV -Label 'Error Message' -Value $_.Exception.Message
    Write-Section -Type 'error' -Name 'FINAL STATUS'
    Write-Host 'Reboot was not scheduled'
    Write-Section -Type 'error' -Name 'SCRIPT COMPLETED'
    exit 1
}
