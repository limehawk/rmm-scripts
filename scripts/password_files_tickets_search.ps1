<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Search Password Files (Tickets)                              v1.0.2
 AUTHOR   : Limehawk.io
 DATE     : January 2026
 USAGE    : .\password_files_tickets_search.ps1
================================================================================
 FILE     : password_files_tickets_search.ps1
 DESCRIPTION : Searches for password files and creates SuperOps tickets
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Scans all user profiles on a Windows machine for files that may contain
   passwords or credentials. Creates a SuperOps ticket assigned to the
   requester associated with the asset when findings are detected.

 DATA SOURCES & PRIORITY

   - Windows Search Index: Fast search if directories are indexed
   - Filesystem: Direct recursive search as fallback
   - SuperOps API: Asset lookup and ticket creation

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $searchPatterns: Array of filename patterns to match
     - $subDirectories: User subdirectories to search
     - $apiKey: SuperOps API key (SuperOps replaces $SuperOpsApiKey)
     - $googleChatWebhookUrl: Optional Google Chat webhook

 SETTINGS

   Configuration details and default values:
     - Search patterns include: *password*, *credential*, *creds*, *logins*, etc.
     - Subdirectories: Desktop, Documents, Downloads, Pictures, cloud folders
     - Tickets created with HIGH priority for critical findings
     - Webhook alert optional (in addition to ticket)

 BEHAVIOR

   The script performs the following actions in order:
   1. Enumerates all user profiles in C:\Users
   2. Searches for password/credential files
   3. Separates critical findings from regular findings
   4. Looks up asset in SuperOps by hostname
   5. Creates ticket assigned to the asset's requester
   6. Optionally sends Google Chat webhook alert

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges (to access other user profiles)
   - SuperOps API key with ticket creation permissions

 SECURITY NOTES

   - API key should be stored securely in SuperOps variables
   - Read-only file operation - does not modify or delete files
   - File contents are NOT read, only metadata reported

 ENDPOINTS

   - SuperOps GraphQL API: https://api.superops.ai/graphql
   - Google Chat Webhook: Optional alert destination

 EXIT CODES

   0 = Success (search completed, ticket created if findings)
   1 = Failure (error occurred)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   All required inputs are valid

   [RUN] SEARCHING FILESYSTEM
   ==============================================================
   Found 3 potential password files

   [RUN] SUPEROPS INTEGRATION
   ==============================================================
   Asset lookup : SUCCESS
   Client : Acme Corp
   Requester : John Smith
   Ticket created : INC-2026-0042

   [OK] FINAL STATUS
   ==============================================================
   Result : SUCCESS
   Files Found : 3
   Ticket : INC-2026-0042

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-01-19 v1.0.2 Updated to two-line ASCII console output style
 2026-01-13 v1.0.1 Add required source field to createTicket API call
 2026-01-13 v1.0.0 Initial release with SuperOps ticket integration
================================================================================
#>
$ErrorActionPreference = 'Stop'

# ============================================================================
# STATE VARIABLES
# ============================================================================
$errorOccurred = $false
$errorText = ""
$foundFiles = @()
$ticketId = $null

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$searchPatterns = @(
    '*password*',
    '*credential*',
    '*creds*',
    '*logins*',
    '*login.csv',
    '*login.xlsx',
    '*login.txt'
)

# Critical patterns - high priority security concerns
# These files should NEVER exist on endpoints
$criticalPatterns = @(
    '*1Password Emergency Kit*',
    '*Emergency Kit*.pdf',
    '*BitWarden*backup*',
    '*KeePass*.kdbx',
    '*LastPass*export*',
    '*master password*',
    '*recovery key*',
    '*seed phrase*',
    '*private key*.pem',
    '*id_rsa'
)

$subDirectories = @(
    'Desktop',
    'Documents',
    'Downloads',
    'Pictures',
    'OneDrive',
    'OneDrive - *',
    'Dropbox',
    'Google Drive',
    'Box'
)

$useIndex = $true
$maxDepth = 10

$excludedProfiles = @(
    'Public',
    'Default',
    'Default User',
    'All Users'
)

# SuperOps API configuration - SuperOps replaces $SuperOpsApiKey at runtime
$apiKey = "$SuperOpsApiKey"
$superOpsApiUrl = "https://api.superops.ai/graphql"

# Google Chat webhook URL - SuperOps replaces $GoogleChatWebhook at runtime
# Leave as placeholder to disable webhook alerts
$googleChatWebhookUrl = "$GoogleChatWebhook"

# Ticket settings
$ticketCategory = "Security"
$ticketSubcategory = "Data Protection"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

Set-StrictMode -Version Latest

function Invoke-SuperOpsGraphQL {
    param (
        [string]$Query,
        [hashtable]$Variables = @{}
    )

    $body = @{
        query = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri $superOpsApiUrl -Method Post -Headers @{
            "Authorization" = "Bearer $apiKey"
            "Content-Type" = "application/json"
        } -Body $body

        if ($response.errors) {
            Write-Host "GraphQL Error : $($response.errors[0].message)"
            return $null
        }

        return $response.data
    }
    catch {
        Write-Host "API Error : $($_.Exception.Message)"
        return $null
    }
}

function Get-AssetByHostname {
    param ([string]$Hostname)

    $query = @'
query getAssetList($input: ListInfoInput!) {
  getAssetList(input: $input) {
    assets {
      assetId
      name
      hostName
      client {
        accountId
        name
      }
      site {
        id
        name
      }
      requester {
        userId
        name
      }
    }
  }
}
'@

    $variables = @{
        input = @{
            page = 1
            pageSize = 1
            condition = @{
                attribute = "hostName"
                operator = "is"
                value = $Hostname
            }
        }
    }

    $result = Invoke-SuperOpsGraphQL -Query $query -Variables $variables

    if ($result -and $result.getAssetList.assets.Count -gt 0) {
        return $result.getAssetList.assets[0]
    }

    return $null
}

function New-SecurityTicket {
    param (
        [string]$ClientId,
        [string]$SiteId,
        [string]$RequesterId,
        [string]$Subject,
        [string]$Description,
        [string]$Priority = "Medium"
    )

    $query = @'
mutation createTicket($input: CreateTicketInput!) {
  createTicket(input: $input) {
    ticketId
    displayId
    subject
    status
  }
}
'@

    $variables = @{
        input = @{
            subject = $Subject
            description = $Description
            client = @{ accountId = $ClientId }
            priority = $Priority
            status = "New"
            source = "INTEGRATION"
        }
    }

    # Add optional fields if provided
    if ($SiteId) {
        $variables.input.site = @{ id = $SiteId }
    }
    if ($RequesterId) {
        $variables.input.requester = @{ userId = $RequesterId }
    }

    $result = Invoke-SuperOpsGraphQL -Query $query -Variables $variables

    if ($result -and $result.createTicket) {
        return $result.createTicket
    }

    return $null
}

function Search-WithIndex {
    param (
        [string[]]$Patterns,
        [string[]]$Paths
    )

    $results = @()

    try {
        $connection = New-Object -ComObject ADODB.Connection
        $recordset = New-Object -ComObject ADODB.Recordset
        $connection.Open("Provider=Search.CollatorDSO;Extended Properties='Application=Windows';")

        foreach ($pattern in $Patterns) {
            $searchPattern = $pattern.Replace('*', '%')

            $pathConditions = ($Paths | ForEach-Object {
                "SCOPE='file:$_'"
            }) -join ' OR '

            $query = @"
SELECT System.ItemPathDisplay, System.Size, System.DateModified
FROM SystemIndex
WHERE System.FileName LIKE '$searchPattern'
AND ($pathConditions)
"@

            $recordset.Open($query, $connection)

            while (-not $recordset.EOF) {
                $sizeValue = $recordset.Fields.Item("System.Size").Value
                $modifiedValue = $recordset.Fields.Item("System.DateModified").Value

                $results += [PSCustomObject]@{
                    Path = $recordset.Fields.Item("System.ItemPathDisplay").Value
                    Size = if ($null -eq $sizeValue -or $sizeValue -is [DBNull]) { 0 } else { [long]$sizeValue }
                    Modified = if ($null -eq $modifiedValue -or $modifiedValue -is [DBNull]) { $null } else { $modifiedValue }
                }
                $recordset.MoveNext()
            }
            $recordset.Close()
        }

        $connection.Close()
    }
    catch {
        return $null
    }

    return $results
}

function Search-Filesystem {
    param (
        [string[]]$Patterns,
        [string[]]$Paths,
        [int]$Depth
    )

    $results = @()

    foreach ($path in $Paths) {
        if (-not (Test-Path $path -PathType Container)) {
            continue
        }

        foreach ($pattern in $Patterns) {
            try {
                $files = Get-ChildItem -Path $path -Filter $pattern -Recurse -File -Depth $Depth -ErrorAction SilentlyContinue

                foreach ($file in $files) {
                    $results += [PSCustomObject]@{
                        Path = $file.FullName
                        Size = $file.Length
                        Modified = $file.LastWriteTime
                    }
                }
            }
            catch {
                # Continue on access denied errors
            }
        }
    }

    return $results
}

function Format-FileSize {
    param ([long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Build-TicketDescription {
    param (
        [string]$Hostname,
        [PSCustomObject[]]$CriticalFiles,
        [PSCustomObject[]]$RegularFiles
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $totalCount = $CriticalFiles.Count + $RegularFiles.Count

    $description = @"
## Password Files Security Alert

A security scan detected files that may contain passwords or credentials on this computer.

**Hostname:** $Hostname
**Scan Time:** $timestamp
**Total Files Found:** $totalCount
**Critical Findings:** $($CriticalFiles.Count)

---

"@

    if ($CriticalFiles.Count -gt 0) {
        $description += @"
### [!] CRITICAL FINDINGS

These files require immediate attention:

"@
        foreach ($file in $CriticalFiles) {
            $description += "- ``$($file.Path)```n"
        }
        $description += "`n---`n`n"
    }

    if ($RegularFiles.Count -gt 0) {
        $description += @"
### Other Findings

"@
        foreach ($file in $RegularFiles | Select-Object -First 20) {
            $description += "- ``$($file.Path)```n"
        }
        if ($RegularFiles.Count -gt 20) {
            $description += "`n*... and $($RegularFiles.Count - 20) more files*`n"
        }
    }

    $description += @"

---

### Recommended Actions

1. Review each file to determine if it contains sensitive information
2. Move legitimate password files to a secure password manager
3. Delete files that are no longer needed
4. Ensure no plaintext passwords are stored on this computer

*This ticket was automatically generated by the Password Files Security Scan.*
"@

    return $description
}

function Send-GoogleChatAlert {
    param (
        [string]$WebhookUrl,
        [string]$Hostname,
        [int]$FileCount,
        [PSCustomObject[]]$Files,
        [PSCustomObject[]]$CriticalFiles,
        [string]$TicketId
    )

    # Check if placeholder was replaced
    if ([string]::IsNullOrWhiteSpace($WebhookUrl) -or $WebhookUrl -eq '$' + 'GoogleChatWebhook') {
        return $false
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $criticalCount = if ($CriticalFiles) { $CriticalFiles.Count } else { 0 }

    # Build critical files section
    $criticalSection = ""
    if ($criticalCount -gt 0) {
        $criticalList = ($CriticalFiles | ForEach-Object {
            "  [!] $($_.Path)"
        }) -join "`n"
        $criticalSection = @"

[!!!] CRITICAL FINDINGS [$criticalCount]
$criticalList

------------------------------
"@
    }

    # Build regular files list (excluding critical)
    $regularFiles = $Files | Where-Object { $file = $_; -not ($CriticalFiles | Where-Object { $_.Path -eq $file.Path }) }
    $fileList = ($regularFiles | Select-Object -First 10 | ForEach-Object {
        "  - $($_.Path)"
    }) -join "`n"

    if ($regularFiles.Count -gt 10) {
        $fileList += "`n  ... and $($regularFiles.Count - 10) more"
    }

    $ticketLine = if ($TicketId) { "ticket ............ $TicketId" } else { "" }

    $messageText = @"
``````
> PASSWORD FILES FOUND

hostname .......... $Hostname
timestamp ......... $timestamp
files found ....... $FileCount
critical .......... $criticalCount
$ticketLine
$criticalSection
$fileList
``````
"@

    $message = @{
        text = $messageText
    } | ConvertTo-Json -Compress

    try {
        $null = Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType 'application/json' -Body $message
        return $true
    }
    catch {
        Write-Host "Warning : Failed to send webhook alert"
        Write-Host "Error   : $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

# Check if API key placeholder was replaced
$apiKeyConfigured = -not [string]::IsNullOrWhiteSpace($apiKey) -and $apiKey -ne ('$' + 'SuperOpsApiKey')

if (-not $apiKeyConfigured) {
    Write-Host "Warning : SuperOps API key not configured"
    Write-Host "          Tickets will not be created"
}

if ($searchPatterns.Count -eq 0) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- At least one search pattern is required"
}

if ($subDirectories.Count -eq 0) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- At least one subdirectory is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    exit 1
}

Write-Host "All required inputs are valid"

# ============================================================================
# ENUMERATE USER PROFILES
# ============================================================================
Write-Host ""
Write-Host "[INFO] ENUMERATING USER PROFILES"
Write-Host "=============================================================="

$usersPath = "C:\Users"
$userProfiles = @()

try {
    $profileFolders = Get-ChildItem -Path $usersPath -Directory -ErrorAction Stop

    foreach ($folder in $profileFolders) {
        if ($excludedProfiles -notcontains $folder.Name) {
            $userProfiles += $folder.FullName
            Write-Host "Profile : $($folder.Name)"
        }
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] ENUMERATION FAILED"
    Write-Host "=============================================================="
    Write-Host "Failed to enumerate user profiles"
    Write-Host "Error : $($_.Exception.Message)"
    Write-Host ""
    exit 1
}

if ($userProfiles.Count -eq 0) {
    Write-Host "No user profiles found"
    Write-Host ""
    Write-Host "[OK] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Result : SUCCESS"
    Write-Host "Files Found : 0"
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "Found $($userProfiles.Count) user profile(s)"

# ============================================================================
# BUILD TARGET PATHS
# ============================================================================
$targetPaths = @()

foreach ($profile in $userProfiles) {
    foreach ($subDir in $subDirectories) {
        if ($subDir -like '*`**') {
            $wildcardPath = Join-Path $profile $subDir
            $matchedPaths = Get-ChildItem -Path (Split-Path $wildcardPath -Parent) -Directory -Filter (Split-Path $wildcardPath -Leaf) -ErrorAction SilentlyContinue
            foreach ($matched in $matchedPaths) {
                $targetPaths += $matched.FullName
            }
        }
        else {
            $fullPath = Join-Path $profile $subDir
            if (Test-Path $fullPath -PathType Container) {
                $targetPaths += $fullPath
            }
        }
    }
}

# ============================================================================
# SEARCH
# ============================================================================
$indexUsed = $false

if ($useIndex) {
    Write-Host ""
    Write-Host "[RUN] SEARCHING INDEX"
    Write-Host "=============================================================="
    Write-Host "Attempting Windows Search Index query"

    $indexResults = Search-WithIndex -Patterns $searchPatterns -Paths $targetPaths

    if ($null -ne $indexResults) {
        $foundFiles = $indexResults
        $indexUsed = $true
        Write-Host "Index search completed"
        Write-Host "Results from index : $($foundFiles.Count)"
    }
    else {
        Write-Host "Index unavailable or query failed, falling back to filesystem"
    }
}

if (-not $indexUsed) {
    Write-Host ""
    Write-Host "[RUN] SEARCHING FILESYSTEM"
    Write-Host "=============================================================="
    Write-Host "Searching $($targetPaths.Count) directories across $($userProfiles.Count) profile(s)"
    Write-Host "Search patterns : $($searchPatterns -join ', ')"
    Write-Host "Max depth : $maxDepth"

    $foundFiles = Search-Filesystem -Patterns $searchPatterns -Paths $targetPaths -Depth $maxDepth
}

# ============================================================================
# RESULTS
# ============================================================================
Write-Host ""
Write-Host "[INFO] RESULTS"
Write-Host "=============================================================="

$uniqueFiles = $foundFiles | Sort-Object -Property Path -Unique

# Separate critical from regular findings
$criticalFiles = @()
$regularFiles = @()

foreach ($file in $uniqueFiles) {
    $isCritical = $false
    foreach ($pattern in $criticalPatterns) {
        if ($file.Path -like $pattern) {
            $isCritical = $true
            break
        }
    }
    if ($isCritical) {
        $criticalFiles += $file
    } else {
        $regularFiles += $file
    }
}

if ($uniqueFiles.Count -eq 0) {
    Write-Host "No password or credential files found"
}
else {
    Write-Host "Found $($uniqueFiles.Count) potential password file(s)"
    Write-Host "Critical : $($criticalFiles.Count)"
    Write-Host ""

    # Display critical findings
    if ($criticalFiles.Count -gt 0) {
        Write-Host "[!] CRITICAL FINDINGS"
        foreach ($file in $criticalFiles) {
            Write-Host "  $($file.Path)"
        }
        Write-Host ""
    }

    # Display regular findings (summary)
    if ($regularFiles.Count -gt 0) {
        Write-Host "Other findings : $($regularFiles.Count)"
        foreach ($file in $regularFiles | Select-Object -First 5) {
            Write-Host "  $($file.Path)"
        }
        if ($regularFiles.Count -gt 5) {
            Write-Host "  ... and $($regularFiles.Count - 5) more"
        }
        Write-Host ""
    }

    # ============================================================================
    # SUPEROPS TICKET CREATION
    # ============================================================================
    if ($apiKeyConfigured) {
        Write-Host "[RUN] SUPEROPS INTEGRATION"
        Write-Host "=============================================================="

        $hostname = $env:COMPUTERNAME
        Write-Host "Looking up asset : $hostname"

        $asset = Get-AssetByHostname -Hostname $hostname

        if ($asset) {
            Write-Host "Asset found : $($asset.name)"
            Write-Host "Client : $($asset.client.name)"
            Write-Host "Requester : $($asset.requester.name)"

            # Determine priority based on critical findings
            $priority = if ($criticalFiles.Count -gt 0) { "High" } else { "Medium" }

            # Build ticket subject
            $subject = "[Security] Password files found on $hostname"
            if ($criticalFiles.Count -gt 0) {
                $subject = "[CRITICAL] Password files found on $hostname"
            }

            # Build ticket description
            $description = Build-TicketDescription -Hostname $hostname -CriticalFiles $criticalFiles -RegularFiles $regularFiles

            Write-Host "Creating ticket..."

            $ticket = New-SecurityTicket `
                -ClientId $asset.client.accountId `
                -SiteId $asset.site.id `
                -RequesterId $asset.requester.userId `
                -Subject $subject `
                -Description $description `
                -Priority $priority

            if ($ticket) {
                $ticketId = $ticket.displayId
                Write-Host "Ticket created : $ticketId"
            }
            else {
                Write-Host "Warning : Failed to create ticket"
            }
        }
        else {
            Write-Host "Warning : Asset not found in SuperOps"
            Write-Host "          Ticket not created"
        }
        Write-Host ""
    }

    # ============================================================================
    # WEBHOOK ALERT (OPTIONAL)
    # ============================================================================
    $webhookConfigured = -not [string]::IsNullOrWhiteSpace($googleChatWebhookUrl) -and $googleChatWebhookUrl -ne ('$' + 'GoogleChatWebhook')
    if ($webhookConfigured) {
        Write-Host "[INFO] WEBHOOK ALERT"
        Write-Host "=============================================================="
        $hostname = $env:COMPUTERNAME
        $sent = Send-GoogleChatAlert -WebhookUrl $googleChatWebhookUrl -Hostname $hostname -FileCount $uniqueFiles.Count -Files $uniqueFiles -CriticalFiles $criticalFiles -TicketId $ticketId
        if ($sent) {
            Write-Host "Alert sent to Google Chat"
        }
        Write-Host ""
    }
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="
Write-Host "Result : SUCCESS"
Write-Host "Files Found : $($uniqueFiles.Count)"
Write-Host "Critical : $($criticalFiles.Count)"
if ($ticketId) {
    Write-Host "Ticket : $ticketId"
}
Write-Host "Search Method : $(if ($indexUsed) { 'Windows Search Index' } else { 'Filesystem' })"

Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="
Write-Host ""

exit 0
