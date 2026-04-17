Import-Module $SuperOpsModule
$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Rename Workstation Manual                                   v8.2.4
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\workstation_rename_manual.ps1
================================================================================
 FILE     : workstation_rename_manual.ps1
 DESCRIPTION : Renames Windows device with custom client segment override
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Rename a Windows device and sync the same name to SuperOps.

   Naming (Windows-legal; max 15 chars; no trailing hyphen):
     CLIENT-USERUUID
       CLIENT : Custom override $YourCustomClientHere, else from $YourClientNameHere
                Variable length; sanitized A-Z0-9; trimmed if needed to ensure fit.
       USER   : Sanitized username; maximized; truncated if needed to ensure fit.
       UUID   : SMBIOS UUID tail; at least 3 chars; trimmed to fill exactly 15.

   Notes:
     - Only A-Z, 0-9, and hyphen used.
     - Name never starts or ends with '-'.
     - Always exactly 15 chars.
     - SuperOps asset name is updated to match.

 DATA SOURCES & PRIORITY

   1. SuperOps runtime placeholders ($YourApiKeyHere, $YourCustomClientHere, etc.)
   2. System information (UUID, username, hostname)
   3. Hardcoded settings (subdomain, segment lengths)

 REQUIRED INPUTS

   All inputs are SuperOps runtime placeholders:
     - $YourApiKeyHere          : SuperOps API key
     - $YourCustomClientHere    : Custom client segment (overrides auto 3-char)
     - $YourAssetIdHere         : SuperOps asset ID
     - $YourAssetNameHere       : Current asset name (for logging)
     - $YourClientNameHere      : Client name (fallback if no custom segment)

 SETTINGS

   - MaxUserSegmentLen: 8 characters
   - MinUuidSuffixLen: 3 characters
   - MaxHostLen: 15 characters (Windows limit)
   - GraphQL endpoint: https://api.superops.ai/msp

 BEHAVIOR

   1. Validates SuperOps API key and asset ID
   2. Uses custom client segment if provided, else 3-char from client name
   3. Retrieves system UUID and logged-in username
   4. Builds hostname: CLIENT-USERUUID (exactly 15 chars)
   5. Renames computer if name differs from current
   6. Updates SuperOps asset name via GraphQL API
   7. Reports final status

 PREREQUISITES

   - Windows 10/11
   - Admin privileges required
   - SuperOps agent installed
   - Internet access for SuperOps API

 SECURITY NOTES

   - API key passed via SuperOps runtime variable
   - No secrets written to permanent logs
   - GraphQL mutation updates asset name only

 ENDPOINTS

   - https://api.superops.ai/msp (SuperOps GraphQL API)

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] SUPEROPS VARIABLES
   ==============================================================
   AssetId (placeholder)    : 12345
   AssetName (placeholder)  : DESKTOP-ABC123
   ClientName (placeholder) : Acme Corp
   CustomClient (runtime)   : ACMECORP
   Subdomain (hardcoded)    : limehawk
   MaxUserSegmentLen        : 8

   [INFO] RAW SYSTEM VALUES
   ==============================================================
   ENV USERNAME             : jsmith
   CIM UserName             : ACME\jsmith
   Current HostName (CIM)   : DESKTOP-ABC123
   SMBIOS UUID              : 12345678-1234-1234-1234-123456789ABC

   [INFO] DERIVED SEGMENTS
   ==============================================================
   CLIENT SEGMENT           : ACMECORP
   USER SEGMENT             : JSM
   DESIRED/OS NAME          : ACMECORP-JSM9ABC
   Name Length              : 15

   [RUN] RENAME ACTION
   ==============================================================
   CURRENT NAME(S)          : DESKTOP-ABC123
   STATUS                   : RENAMING TO ACMECORP-JSM9ABC
   NOTE                     : CHANGE TAKES EFFECT AFTER REBOOT
   RESULT                   : RENAME COMMAND ISSUED

   [RUN] SUPEROPS SYNC
   ==============================================================
   RESULT                   : SUPEROPS ASSET NAME UPDATED

   [OK] FINAL STATUS
   ==============================================================
   RENAME SCHEDULED IF NEEDED. REBOOT TO APPLY NEW HOSTNAME
   SUPEROPS ASSET NAME SYNCED

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v8.2.4 Updated to two-line ASCII console output style
 2026-01-14 v8.2.3 Added complete README sections for framework compliance
 2025-12-23 v8.2.2 Updated to Limehawk Script Framework
 2024-12-01 v8.2.1 Fixed StrictMode error checking GraphQL response for errors
 2025-08-20 v8.2.0 Clarified README: client segment is variable length; no "CLIENT3"
 2025-08-19 v8.1.0 Pattern CLIENT-USERUUID, min UUID=3, maximize USER, exact 15
 2025-08-19 v8.0.x No separators prototype, experimental
 2025-08-19 v7.4.1 Fixed PS5.1 syntax issues; removed ternary shorthand
 2025-08-19 v7.4.0 Added benign rename error handling; canonical name check
 2025-08-19 v7.3.x Added full README in Style A; standardized headers
 2025-08-19 v7.2.x Brand segment always first word; UUID always appended
 2025-08-19 v7.0 Introduced manual client override ($YourCustomClientHere)
 2025-08-19 v6.x Split branch from autoname for manual override use-case
 2025-08-19 v5.x CLIENT/BRAND/USER baseline pattern; SuperOps sync
 2025-08-19 v4.x Added GraphQL mutation to update SuperOps asset
 2025-08-19 v3.x Introduced sanitization helpers & diagnostics
 2025-08-19 v1-2.x Early rename iterations (no SuperOps sync)
================================================================================
#>

# ============================== SETTINGS =====================================
$SUPEROPS_API_KEY        = "$YourApiKeyHere"
$CUSTOM_CLIENT_SEG_INPUT = "$YourCustomClientHere"
$SUPEROPS_SUBDOMAIN      = "limehawk"
$ASSET_ID                = $YourAssetIdHere
$ASSET_NAME_PLACEHOLDER  = $YourAssetNameHere
$CLIENT_NAME_INPUT       = $YourClientNameHere

$MaxUserSegmentLen       = 8
$MinUuidSuffixLen        = 3
$MaxHostLen              = 15
$GraphQlEndpoint         = "https://api.superops.ai/msp"
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
    param([string]$s,[int]$maxLen=0)
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $t = ($s.ToUpper() -replace '[^A-Z0-9]', '')
    if ($maxLen -gt 0 -and $t.Length -gt $maxLen) { return $t.Substring(0,$maxLen) }
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
    param(
        [string]$Client, [string]$User, [string]$UuidClean,
        [int]$MaxLen = 15, [int]$MinUuid = 3
    )
    if ([string]::IsNullOrWhiteSpace($UuidClean)) { throw "UUID EMPTY" }
    $client = SanitizeSegment $Client
    $user   = SanitizeSegment -s $User -maxLen $MaxUserSegmentLen
    $uuid   = $UuidClean.Replace('-','').ToUpper()

    $maxClientLen = $MaxLen - 1 - $MinUuid
    if ($client.Length -gt $maxClientLen) { $client = $client.Substring(0,$maxClientLen) }

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
function Write-Section { param([string]$title, [string]$status = "INFO"); Write-Host ""; Write-Host ("[$status] $title"); Write-Host ("=" * 62) }
function PrintKV([string]$label, [string]$value) { $lbl = $label.PadRight(24); Write-Host (" {0} : {1}" -f $lbl, $value) }
# ============================================================================

# =============================================================================
# MAIN
# =============================================================================
Write-Section "SUPEROPS VARIABLES"
PrintKV "AssetId (placeholder)"      $ASSET_ID
PrintKV "AssetName (placeholder)"    $ASSET_NAME_PLACEHOLDER
PrintKV "ClientName (placeholder)"   $CLIENT_NAME_INPUT
PrintKV "CustomClient (runtime)"     $CUSTOM_CLIENT_SEG_INPUT
PrintKV "Subdomain (hardcoded)"      $SUPEROPS_SUBDOMAIN
PrintKV "MaxUserSegmentLen"          $MaxUserSegmentLen

$ENV_USERNAME  = $env:USERNAME
$CIM_CS        = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$CIM_USER      = $CIM_CS.UserName
$CIM_HOST      = $CIM_CS.Name
$UUID_RAW      = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue | Select-Object -ExpandProperty UUID

Write-Section "RAW SYSTEM VALUES"
PrintKV "ENV USERNAME"               $ENV_USERNAME
PrintKV "CIM UserName"               $CIM_USER
PrintKV "Current HostName (CIM)"     $CIM_HOST
PrintKV "SMBIOS UUID"                $UUID_RAW

try {
    if ([string]::IsNullOrWhiteSpace($SUPEROPS_API_KEY))   { throw "MISSING API KEY" }
    if ([string]::IsNullOrWhiteSpace($ASSET_ID))           { throw "MISSING ASSET ID" }
    if ([string]::IsNullOrWhiteSpace($UUID_RAW))           { throw "UUID NOT FOUND" }

    $CLIENT_SEG = SanitizeSegment -s $CUSTOM_CLIENT_SEG_INPUT
    if ([string]::IsNullOrWhiteSpace($CLIENT_SEG)) {
        if ([string]::IsNullOrWhiteSpace($CLIENT_NAME_INPUT)) { throw "CLIENT NAME NOT FOUND" }
        $CLIENT_SEG = Get-Abbr3 -s $CLIENT_NAME_INPUT
    }

    $LOGGEDINUSER = $ENV_USERNAME
    if ([string]::IsNullOrWhiteSpace($LOGGEDINUSER) -and $CIM_USER) { $LOGGEDINUSER = ($CIM_USER -split '\\')[-1] }
    $USER_SEG = SanitizeSegment -s $LOGGEDINUSER -maxLen $MaxUserSegmentLen

    $uuidClean = $UUID_RAW.Replace('-','').ToUpper()
    $DESIRED_NAME = Build-ClientUserUuidHyphenName -Client $CLIENT_SEG -User $USER_SEG -UuidClean $uuidClean -MaxLen $MaxHostLen -MinUuid $MinUuidSuffixLen

    Write-Section "DERIVED SEGMENTS" "INFO"
    PrintKV "CLIENT SEGMENT"          $CLIENT_SEG
    PrintKV "USER SEGMENT"            ($(if ($USER_SEG) { $USER_SEG } else { "<none>" }))
    PrintKV "DESIRED/OS NAME"         $DESIRED_NAME
    PrintKV "Name Length"             ($DESIRED_NAME.Length.ToString())

    $CanonicalNow = Get-CanonicalHostNames
    Write-Section "RENAME ACTION" "RUN"
    PrintKV "CURRENT NAME(S)"         ($CanonicalNow -join ", ")

    if ($CanonicalNow -contains $DESIRED_NAME) {
        PrintKV "STATUS"              "CURRENT HOSTNAME ALREADY MATCHES"
    } else {
        PrintKV "STATUS"              ("RENAMING TO " + $DESIRED_NAME)
        PrintKV "NOTE"                "CHANGE TAKES EFFECT AFTER REBOOT"
        try {
            Rename-Computer -NewName $DESIRED_NAME -Force -PassThru | Out-Null
            PrintKV "RESULT"          "RENAME COMMAND ISSUED"
        } catch {
            $em = $_.Exception.Message
            if (Is-BenignRenameError $em) {
                PrintKV "RESULT"      "RENAME SKIPPED: ALREADY SET"
            } else {
                PrintKV "RESULT"      ("RENAME WARNING: " + $em)
            }
        }
    }

    Write-Section "SUPEROPS SYNC" "RUN"
    $headers = @{
        "Content-Type"      = "application/json"
        "CustomerSubDomain" = $SUPEROPS_SUBDOMAIN
        "Authorization"     = "Bearer $SUPEROPS_API_KEY"
    }
    $mutation = @'
mutation updateAsset($input: UpdateAssetInput!) {
  updateAsset(input: $input) {
    assetId
    name
  }
}
'@
    $variables = @{ input = @{ assetId = $ASSET_ID; name = $DESIRED_NAME } }
    $body = @{ query = $mutation; variables = $variables } | ConvertTo-Json -Depth 6 -Compress
    $resp = Invoke-RestMethod -Uri $GraphQlEndpoint -Method POST -Headers $headers -Body $body
    if ($resp.PSObject.Properties['errors'] -and $resp.errors) { throw ("SUPEROPS ERROR: " + ($resp.errors | ConvertTo-Json -Compress)) }
    PrintKV "RESULT"                  "SUPEROPS ASSET NAME UPDATED"

    Write-Section "FINAL STATUS" "OK"
    Write-Host " RENAME SCHEDULED IF NEEDED. REBOOT TO APPLY NEW HOSTNAME"
    Write-Host " SUPEROPS ASSET NAME SYNCED"
    Write-Section "SCRIPT COMPLETED" "OK"
    exit 0
}
catch {
    Write-Host ""
    Write-Section "ERROR OCCURRED" "ERROR"
    PrintKV "ERROR MESSAGE" ($_.Exception.Message.ToUpper())
    exit 1
}
