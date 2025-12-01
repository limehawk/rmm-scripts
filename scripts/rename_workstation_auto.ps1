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
 SCRIPT    : rename_workstation_auto.ps1
 VERSION   : v8.2.1
================================================================================
 README
--------------------------------------------------------------------------------
 PURPOSE
   Rename a Windows device and sync the same name to SuperOps.

   Naming (Windows-legal; max 15 chars; no trailing hyphen):
     CLIENT3-USERUUID
       CLIENT3 : 3-char abbreviation of $YourClientNameHere (always forced).
       USER    : Sanitized username; maximized; truncated if needed.
       UUID    : SMBIOS UUID tail; at least 3 chars; trimmed to fill exactly 15.

   Notes:
     - Only A–Z, 0–9, and hyphen used.
     - Name never starts or ends with '-'.
     - Always exactly 15 chars.
     - SuperOps asset name is updated to match.

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 v8.2.1  (2024-12-01)  Fixed StrictMode error checking GraphQL response for errors.
 v8.2.0  (2025-08-20)  Clarified README: auto script enforces 3-char client code.
 v8.1.0  (2025-08-19)  Pattern CLIENT-USERUUID, min UUID=3, maximize USER, exact 15.
 v8.0.x  (2025-08-19)  No separators prototype, experimental.
 v7.4.1  (2025-08-19)  Fixed PS5.1 syntax issues; removed ternary shorthand.
 v7.4.0  (2025-08-19)  Added benign rename error handling; canonical name check.
 v7.3.x  (2025-08-19)  Added full README in Style A; standardized headers.
 v7.2.x  (2025-08-19)  Brand segment always first word; UUID always appended.
 v7.0    (2025-08-19)  Structured diagnostics improvements.
 v6.x    (2025-08-19)  Split branch from manualname; preserved 3-char client.
 v5.x    (2025-08-19)  CLIENT/BRAND/USER baseline pattern; SuperOps sync.
 v4.x    (2025-08-19)  Added GraphQL mutation to update SuperOps asset.
 v3.x    (2025-08-19)  Introduced sanitization helpers & diagnostics.
 v1–2.x  (2025-08-19)  Early rename iterations (no SuperOps sync).
================================================================================
#>

Set-StrictMode -Version Latest

# ============================== SETTINGS =====================================
$SUPEROPS_API_KEY        = "$YourApiKeyHere"
$SUPEROPS_SUBDOMAIN      = "limehawk"
$ASSET_ID                = $YourAssetIdHere
$ASSET_NAME_PLACEHOLDER  = $YourAssetNameHere
$CLIENT_NAME_INPUT       = $YourClientNameHere

$MaxUserSegmentLen       = 8
$MinUuidSuffixLen        = 3
$MaxHostLen              = 15
$GraphQlEndpoint         = "https://api.superops.ai/msp"
# ============================================================================

# (helpers identical to manualname — but CLIENT_SEG is forced via Get-Abbr3)
# ============================== HELPERS ======================================
function Get-Abbr3 {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $t = ($s.ToUpper() -replace '[^A-Z0-9]', '')
    if ($t.Length -lt 3) { return $t } else { return $t.Substring(0,3) }
}
function SanitizeSegment { param([string]$s,[int]$maxLen=0) if ([string]::IsNullOrWhiteSpace($s)) { return "" } $t = ($s.ToUpper() -replace '[^A-Z0-9]', ''); if ($maxLen -gt 0 -and $t.Length -gt $maxLen) { return $t.Substring(0,$maxLen) } return $t }
function Get-CanonicalHostNames { $n1 = [Environment]::MachineName; $n2 = $env:COMPUTERNAME; $n3 = try { (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Name } catch { $null }; return @($n1, $n2, $n3 | Where-Object { $_ }) | Select-Object -Unique }
function Test-HostSafeName { param([string]$Name) if ($Name.Length -lt 1 -or $Name.Length -gt 15) { return $false } if ($Name.StartsWith('-') -or $Name.EndsWith('-')) { return $false } return ($Name -match '^[A-Z0-9-]{1,15}$') }
function Build-ClientUserUuidHyphenName {
    param([string]$Client3,[string]$User,[string]$UuidClean,[int]$MaxLen=15,[int]$MinUuid=3)
    if ([string]::IsNullOrWhiteSpace($UuidClean)) { throw "UUID EMPTY" }
    $client = Get-Abbr3 -s $Client3
    $user   = SanitizeSegment -s $User -maxLen $MaxUserSegmentLen
    $uuid   = $UuidClean.Replace('-','').ToUpper()

    $maxClientLen = $MaxLen - 1 - $MinUuid
    if ($client.Length -gt $maxClientLen) { $client = $client.Substring(0,$maxClientLen) }

    $prefix = $client + '-'
    $rem = $MaxLen - $prefix.Length
    if ($rem -lt $MinUuid) { $client = $client.Substring(0, $MaxLen - 1 - $MinUuid); $prefix = $client + '-'; $rem = $MaxLen - $prefix.Length }

    $maxUserTake = $rem - $MinUuid; if ($maxUserTake -lt 0) { $maxUserTake = 0 }
    $userTake = 0; if (-not [string]::IsNullOrWhiteSpace($user)) { $userTake = [Math]::Min($user.Length, $maxUserTake) }
    $uuidTake = $MaxLen - $prefix.Length - $userTake; if ($uuidTake -lt $MinUuid) { $uuidTake = $MinUuid }
    if ($uuid.Length -lt $uuidTake) { throw "UUID TOO SHORT FOR REQUIRED TAIL" }
    $uuidSuffix = $uuid.Substring($uuid.Length - $uuidTake, $uuidTake)

    $name = ($prefix + $user.Substring(0,$userTake) + $uuidSuffix).ToUpper()
    if (-not (Test-HostSafeName $name)) { throw "BUILT NAME FAILED HOST POLICY: $name" }
    if ($name.Length -ne $MaxLen) { throw "BUILT NAME NOT EXACTLY $MaxLen CHARS: $name" }
    return $name
}
function Is-BenignRenameError { param([string]$msg) if (-not $msg) { return $false } $m=$msg.ToUpper(); return ($m -like "*THE NEW NAME IS THE SAME AS THE CURRENT NAME*") -or ($m -like "*SKIP COMPUTER*" -and $m -like "*SAME AS THE CURRENT NAME*") }
function Write-Section { param([string]$title); Write-Host ""; Write-Host ("[ {0} ]" -f $title); Write-Host ("-" * 62) }
function PrintKV([string]$label,[string]$value){$lbl=$label.PadRight(24);Write-Host (" {0} : {1}" -f $lbl,$value)}
# ============================================================================

# MAIN
Write-Section "SUPEROPS VARIABLES"
PrintKV "AssetId (placeholder)" $ASSET_ID
PrintKV "AssetName (placeholder)" $ASSET_NAME_PLACEHOLDER
PrintKV "ClientName (placeholder)" $CLIENT_NAME_INPUT
PrintKV "Subdomain (hardcoded)" $SUPEROPS_SUBDOMAIN
PrintKV "MaxUserSegmentLen" $MaxUserSegmentLen

$ENV_USERNAME=$env:USERNAME
$CIM_CS=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$CIM_USER=$CIM_CS.UserName
$CIM_HOST=$CIM_CS.Name
$UUID_RAW=Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue|Select-Object -ExpandProperty UUID

Write-Section "RAW SYSTEM VALUES"
PrintKV "ENV USERNAME" $ENV_USERNAME
PrintKV "CIM UserName" $CIM_USER
PrintKV "Current HostName (CIM)" $CIM_HOST
PrintKV "SMBIOS UUID" $UUID_RAW

try {
    if ([string]::IsNullOrWhiteSpace($SUPEROPS_API_KEY)) { throw "MISSING API KEY" }
    if ([string]::IsNullOrWhiteSpace($ASSET_ID)) { throw "MISSING ASSET ID" }
    if ([string]::IsNullOrWhiteSpace($CLIENT_NAME_INPUT)) { throw "CLIENT NAME NOT FOUND" }
    if ([string]::IsNullOrWhiteSpace($UUID_RAW)) { throw "UUID NOT FOUND" }

    $CLIENT_SEG = Get-Abbr3 -s $CLIENT_NAME_INPUT
    $LOGGEDINUSER=$ENV_USERNAME
    if ([string]::IsNullOrWhiteSpace($LOGGEDINUSER) -and $CIM_USER){$LOGGEDINUSER=($CIM_USER -split '\\')[-1]}
    $USER_SEG=SanitizeSegment -s $LOGGEDINUSER -maxLen $MaxUserSegmentLen
    $uuidClean=$UUID_RAW.Replace('-','').ToUpper()
    $DESIRED_NAME=Build-ClientUserUuidHyphenName -Client3 $CLIENT_SEG -User $USER_SEG -UuidClean $uuidClean -MaxLen $MaxHostLen -MinUuid $MinUuidSuffixLen

    Write-Section "DERIVED SEGMENTS"
    PrintKV "CLIENT SEGMENT" $CLIENT_SEG
    PrintKV "USER SEGMENT" ($(if ($USER_SEG){$USER_SEG}else{"<none>"}))
    PrintKV "DESIRED/OS NAME" $DESIRED_NAME
    PrintKV "Name Length" ($DESIRED_NAME.Length.ToString())

    $CanonicalNow=Get-CanonicalHostNames
    Write-Section "RENAME ACTION"
    PrintKV "CURRENT NAME(S)" ($CanonicalNow -join ", ")
    if ($CanonicalNow -contains $DESIRED_NAME){PrintKV "STATUS" "CURRENT HOSTNAME ALREADY MATCHES"}
    else{PrintKV "STATUS" ("RENAMING TO "+$DESIRED_NAME);PrintKV "NOTE" "CHANGE TAKES EFFECT AFTER REBOOT";try{Rename-Computer -NewName $DESIRED_NAME -Force -PassThru|Out-Null;PrintKV "RESULT" "RENAME COMMAND ISSUED"}catch{$em=$_.Exception.Message;if(Is-BenignRenameError $em){PrintKV "RESULT" "RENAME SKIPPED: ALREADY SET"}else{PrintKV "RESULT" ("RENAME WARNING: "+$em)}}}

    Write-Section "SUPEROPS SYNC"
    $headers=@{"Content-Type"="application/json";"CustomerSubDomain"=$SUPEROPS_SUBDOMAIN;"Authorization"="Bearer $SUPEROPS_API_KEY"}
    $mutation=@'
mutation updateAsset($input: UpdateAssetInput!){updateAsset(input:$input){assetId name}}
'@
    $variables=@{input=@{assetId=$ASSET_ID;name=$DESIRED_NAME}}
    $body=@{query=$mutation;variables=$variables}|ConvertTo-Json -Depth 6 -Compress
    $resp=Invoke-RestMethod -Uri $GraphQlEndpoint -Method POST -Headers $headers -Body $body
    if($resp.PSObject.Properties['errors'] -and $resp.errors){throw ("SUPEROPS ERROR: "+($resp.errors|ConvertTo-Json -Compress))}
    PrintKV "RESULT" "SUPEROPS ASSET NAME UPDATED"

    Write-Section "FINAL STATUS"
    Write-Host " RENAME SCHEDULED IF NEEDED. REBOOT TO APPLY NEW HOSTNAME"
    Write-Host " SUPEROPS ASSET NAME SYNCED"
    Write-Section "SCRIPT COMPLETED";exit 0
}catch{Write-Host "";Write-Section "ERROR OCCURRED";PrintKV "ERROR MESSAGE" ($_.Exception.Message.ToUpper());exit 1}
