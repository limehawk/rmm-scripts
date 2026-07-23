$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Rename Workstation Auto                                     v9.0.0
 AUTHOR   : Limehawk.io
 DATE     : July 2026
 USAGE    : .\workstation_rename_auto.ps1
================================================================================
 FILE     : workstation_rename_auto.ps1
 DESCRIPTION : Auto-renames Windows device using CLIENT3-USERUUID (Level)
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Rename a Windows device using CLIENT3-USERUUID (exactly 15 chars).
   Client segment comes from the Level device group name (system variable).
   No external RMM API call — Level inventory follows the OS hostname after reboot.

   Naming (Windows-legal; max 15 chars; no trailing hyphen):
     CLIENT3-USERUUID
       CLIENT3 : 3-char abbreviation of {{level_group_name}}.
       USER    : Sanitized username; maximized; truncated if needed.
       UUID    : SMBIOS UUID tail; at least 3 chars; trimmed to fill exactly 15.

   Notes:
     - Only A-Z, 0-9, and hyphen used.
     - Name never starts or ends with '-'.
     - Always exactly 15 chars.
     - Emits Level output slots DesiredHostname / RenameStatus for automations.

 DATA SOURCES & PRIORITY

   1. Level system variable {{level_group_name}} (device's group)
   2. System information (UUID, username, hostname)
   3. Hardcoded settings (segment lengths)

 REQUIRED INPUTS

   Injected by Level before run (do not replace with SuperOps-style placeholders):
     - {{level_group_name}} : device group name → 3-char client abbreviation

 SETTINGS

   - MaxUserSegmentLen: 8 characters
   - MinUuidSuffixLen: 3 characters
   - MaxHostLen: 15 characters (Windows limit)

 BEHAVIOR

   1. Validates Level group name was interpolated
   2. Retrieves system UUID and logged-in username
   3. Builds hostname: CLIENT3-USERUUID (exactly 15 chars)
   4. Renames computer if name differs from current
   5. Emits Level output slots and reports status
   6. Reboot required for hostname change to take effect

 PREREQUISITES

   - Windows 10/11
   - Admin privileges (Level runAs: SYSTEM)
   - Level agent installed; device assigned to a client group
   - Script must run via Level so {{level_group_name}} is interpolated

 SECURITY NOTES

   - No API keys or secrets
   - No secrets written to permanent logs

 ENDPOINTS

   Not applicable — local rename only

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] LEVEL VARIABLES
   ==============================================================
   Group Name (level)       : Bell Companies
   Device Hostname (level)  : DESKTOP-ABC123
   MaxUserSegmentLen        : 8

   [INFO] RAW SYSTEM VALUES
   ==============================================================
   ENV USERNAME             : jsmith
   CIM UserName             : BELL\jsmith
   Current HostName (CIM)   : DESKTOP-ABC123
   SMBIOS UUID              : 12345678-1234-1234-1234-123456789ABC

   [INFO] DERIVED SEGMENTS
   ==============================================================
   CLIENT SEGMENT           : BEL
   USER SEGMENT             : JSMITH
   DESIRED/OS NAME          : BEL-JSMITH89ABC
   Name Length              : 15

   [RUN] RENAME ACTION
   ==============================================================
   CURRENT NAME(S)          : DESKTOP-ABC123
   STATUS                   : RENAMING TO BEL-JSMITH89ABC
   NOTE                     : CHANGE TAKES EFFECT AFTER REBOOT
   RESULT                   : RENAME COMMAND ISSUED

   [OK] FINAL STATUS
   ==============================================================
   RENAME SCHEDULED IF NEEDED. REBOOT TO APPLY NEW HOSTNAME

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-07-22 v9.0.0 Ported to Level.io: drop SuperOps module/API/placeholders;
                   client from {{level_group_name}}; emit Level output slots
 2026-01-19 v8.2.4 Updated to two-line ASCII console output style
 2026-01-14 v8.2.3 Added complete README sections for framework compliance
 2025-12-23 v8.2.2 Updated to Limehawk Script Framework
 2024-12-01 v8.2.1 Fixed StrictMode error checking GraphQL response for errors
 2025-08-20 v8.2.0 Clarified README: auto script enforces 3-char client code
 2025-08-19 v8.1.0 Pattern CLIENT-USERUUID, min UUID=3, maximize USER, exact 15
 2025-08-19 v8.0.x No separators prototype, experimental
 2025-08-19 v7.4.1 Fixed PS5.1 syntax issues; removed ternary shorthand
 2025-08-19 v7.4.0 Added benign rename error handling; canonical name check
 2025-08-19 v7.3.x Added full README in Style A; standardized headers
 2025-08-19 v7.2.x Brand segment always first word; UUID always appended
 2025-08-19 v7.0 Structured diagnostics improvements
 2025-08-19 v6.x Split branch from manualname; preserved 3-char client
 2025-08-19 v5.x CLIENT/BRAND/USER baseline pattern; SuperOps sync
 2025-08-19 v4.x Added GraphQL mutation to update SuperOps asset
 2025-08-19 v3.x Introduced sanitization helpers & diagnostics
 2025-08-19 v1-2.x Early rename iterations (no SuperOps sync)
================================================================================
#>

# ============================== SETTINGS =====================================
# Level interpolates {{level_*}} system variables into the script body before run.
# Devices should sit under a client group (e.g. "Bell Companies") so the 3-char
# abbreviation is stable and meaningful.
$CLIENT_NAME_INPUT       = "{{level_group_name}}"
$LEVEL_DEVICE_HOSTNAME   = "{{level_device_hostname}}"

$MaxUserSegmentLen       = 8
$MinUuidSuffixLen        = 3
$MaxHostLen              = 15
# ============================================================================

# ============================== HELPERS ======================================

Set-StrictMode -Version Latest

function Get-Abbr3 {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $t = ($s.ToUpper() -replace '[^A-Z0-9]', '')
    if ($t.Length -lt 3) { return $t } else { return $t.Substring(0,3) }
}
function SanitizeSegment {
    param([string]$s, [int]$maxLen = 0)
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $t = ($s.ToUpper() -replace '[^A-Z0-9]', '')
    if ($maxLen -gt 0 -and $t.Length -gt $maxLen) { return $t.Substring(0, $maxLen) }
    return $t
}
function Get-CanonicalHostNames {
    $n1 = [Environment]::MachineName
    $n2 = $env:COMPUTERNAME
    $n3 = try { (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Name } catch { $null }
    return @($n1, $n2, $n3 | Where-Object { $_ }) | Select-Object -Unique
}
function Test-HostSafeName {
    param([string]$Name)
    if ($Name.Length -lt 1 -or $Name.Length -gt 15) { return $false }
    if ($Name.StartsWith('-') -or $Name.EndsWith('-')) { return $false }
    return ($Name -match '^[A-Z0-9-]{1,15}$')
}
function Build-ClientUserUuidHyphenName {
    param([string]$Client3, [string]$User, [string]$UuidClean, [int]$MaxLen = 15, [int]$MinUuid = 3)
    if ([string]::IsNullOrWhiteSpace($UuidClean)) { throw "UUID EMPTY" }
    $client = Get-Abbr3 -s $Client3
    $user   = SanitizeSegment -s $User -maxLen $MaxUserSegmentLen
    $uuid   = $UuidClean.Replace('-', '').ToUpper()

    $maxClientLen = $MaxLen - 1 - $MinUuid
    if ($client.Length -gt $maxClientLen) { $client = $client.Substring(0, $maxClientLen) }

    $prefix = $client + '-'
    $rem = $MaxLen - $prefix.Length
    if ($rem -lt $MinUuid) {
        $client = $client.Substring(0, $MaxLen - 1 - $MinUuid)
        $prefix = $client + '-'
        $rem = $MaxLen - $prefix.Length
    }

    $maxUserTake = $rem - $MinUuid
    if ($maxUserTake -lt 0) { $maxUserTake = 0 }
    $userTake = 0
    if (-not [string]::IsNullOrWhiteSpace($user)) {
        $userTake = [Math]::Min($user.Length, $maxUserTake)
    }
    $uuidTake = $MaxLen - $prefix.Length - $userTake
    if ($uuidTake -lt $MinUuid) { $uuidTake = $MinUuid }
    if ($uuid.Length -lt $uuidTake) { throw "UUID TOO SHORT FOR REQUIRED TAIL" }
    $uuidSuffix = $uuid.Substring($uuid.Length - $uuidTake, $uuidTake)

    $name = ($prefix + $user.Substring(0, $userTake) + $uuidSuffix).ToUpper()
    if (-not (Test-HostSafeName $name)) { throw "BUILT NAME FAILED HOST POLICY: $name" }
    if ($name.Length -ne $MaxLen) { throw "BUILT NAME NOT EXACTLY $MaxLen CHARS: $name" }
    return $name
}
function Is-BenignRenameError {
    param([string]$msg)
    if (-not $msg) { return $false }
    $m = $msg.ToUpper()
    return ($m -like "*THE NEW NAME IS THE SAME AS THE CURRENT NAME*") -or
           ($m -like "*SKIP COMPUTER*" -and $m -like "*SAME AS THE CURRENT NAME*")
}
function Test-LevelInterpolated {
    param([string]$Value, [string]$TokenName)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '\{\{') {
        throw "LEVEL DID NOT INTERPOLATE $TokenName — RUN THIS SCRIPT VIA LEVEL"
    }
    return $true
}
function Write-LevelSlot {
    # Emit a Level script-variable output slot: {{name=value}}
    param([string]$Name, [string]$Value)
    $open = [string][char]123 + [string][char]123
    $close = [string][char]125 + [string][char]125
    Write-Host ($open + $Name + '=' + $Value + $close)
}
function Write-Section {
    param([string]$title, [string]$status = "INFO")
    Write-Host ""
    Write-Host ("[$status] $title")
    Write-Host ("=" * 62)
}
function PrintKV {
    param([string]$label, [string]$value)
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}
# ============================================================================

# MAIN
Write-Section "LEVEL VARIABLES"
PrintKV "Group Name (level)" $CLIENT_NAME_INPUT
PrintKV "Device Hostname (level)" $LEVEL_DEVICE_HOSTNAME
PrintKV "MaxUserSegmentLen" $MaxUserSegmentLen

$ENV_USERNAME = $env:USERNAME
$CIM_CS = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$CIM_USER = if ($CIM_CS) { $CIM_CS.UserName } else { $null }
$CIM_HOST = if ($CIM_CS) { $CIM_CS.Name } else { $null }
$UUID_RAW = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty UUID

Write-Section "RAW SYSTEM VALUES"
PrintKV "ENV USERNAME" $ENV_USERNAME
PrintKV "CIM UserName" $CIM_USER
PrintKV "Current HostName (CIM)" $CIM_HOST
PrintKV "SMBIOS UUID" $UUID_RAW

try {
    [void](Test-LevelInterpolated -Value $CLIENT_NAME_INPUT -TokenName 'level_group_name')
    if ([string]::IsNullOrWhiteSpace($CLIENT_NAME_INPUT)) { throw "CLIENT GROUP NAME EMPTY — ASSIGN DEVICE TO A LEVEL GROUP" }
    if ([string]::IsNullOrWhiteSpace($UUID_RAW)) { throw "UUID NOT FOUND" }

    $CLIENT_SEG = Get-Abbr3 -s $CLIENT_NAME_INPUT
    if ([string]::IsNullOrWhiteSpace($CLIENT_SEG)) { throw "CLIENT SEGMENT EMPTY AFTER SANITIZE" }

    $LOGGEDINUSER = $ENV_USERNAME
    if ([string]::IsNullOrWhiteSpace($LOGGEDINUSER) -and $CIM_USER) {
        $LOGGEDINUSER = ($CIM_USER -split '\\')[-1]
    }
    $USER_SEG = SanitizeSegment -s $LOGGEDINUSER -maxLen $MaxUserSegmentLen
    $uuidClean = $UUID_RAW.Replace('-', '').ToUpper()
    $DESIRED_NAME = Build-ClientUserUuidHyphenName -Client3 $CLIENT_SEG -User $USER_SEG -UuidClean $uuidClean -MaxLen $MaxHostLen -MinUuid $MinUuidSuffixLen

    Write-Section "DERIVED SEGMENTS" "INFO"
    PrintKV "CLIENT SEGMENT" $CLIENT_SEG
    PrintKV "USER SEGMENT" ($(if ($USER_SEG) { $USER_SEG } else { "<none>" }))
    PrintKV "DESIRED/OS NAME" $DESIRED_NAME
    PrintKV "Name Length" ($DESIRED_NAME.Length.ToString())

    $CanonicalNow = Get-CanonicalHostNames
    Write-Section "RENAME ACTION" "RUN"
    PrintKV "CURRENT NAME(S)" ($CanonicalNow -join ", ")
    $renameStatus = "already_matches"
    if ($CanonicalNow -contains $DESIRED_NAME) {
        PrintKV "STATUS" "CURRENT HOSTNAME ALREADY MATCHES"
    } else {
        PrintKV "STATUS" ("RENAMING TO " + $DESIRED_NAME)
        PrintKV "NOTE" "CHANGE TAKES EFFECT AFTER REBOOT"
        try {
            Rename-Computer -NewName $DESIRED_NAME -Force -PassThru | Out-Null
            PrintKV "RESULT" "RENAME COMMAND ISSUED"
            $renameStatus = "scheduled"
        } catch {
            $em = $_.Exception.Message
            if (Is-BenignRenameError $em) {
                PrintKV "RESULT" "RENAME SKIPPED: ALREADY SET"
                $renameStatus = "already_matches"
            } else {
                PrintKV "RESULT" ("RENAME WARNING: " + $em)
                $renameStatus = "warning"
            }
        }
    }

    Write-LevelSlot -Name "DesiredHostname" -Value $DESIRED_NAME
    Write-LevelSlot -Name "RenameStatus" -Value $renameStatus

    Write-Section "FINAL STATUS" "OK"
    Write-Host " RENAME SCHEDULED IF NEEDED. REBOOT TO APPLY NEW HOSTNAME"
    Write-Host " LEVEL FOLLOWS OS HOSTNAME AFTER REBOOT (NO RMM ASSET API)"
    Write-Section "SCRIPT COMPLETED" "OK"
    exit 0
} catch {
    Write-Host ""
    Write-Section "ERROR OCCURRED" "ERROR"
    PrintKV "ERROR MESSAGE" ($_.Exception.Message.ToUpper())
    Write-LevelSlot -Name "RenameStatus" -Value "error"
    exit 1
}
