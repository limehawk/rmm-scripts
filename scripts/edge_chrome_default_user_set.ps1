$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Edge Set Chrome Default                                       v1.2.0
 AUTHOR   : Limehawk.io
 DATE      : December 2025
 USAGE    : .\edge_chrome_default_user_set.ps1
================================================================================
 FILE     : edge_chrome_default_user_set.ps1
 DESCRIPTION : Sets Google Chrome as default browser for current user via SetUserFTA
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Sets Google Chrome as the default browser for the current user. Uses
   SetUserFTA to properly set file associations with the correct UserChoice
   hash that Windows 10/11 requires.

   MUST run as the logged-in user (not SYSTEM) - default browser settings are
   per-user and stored in HKCU with hash validation.

 DATA SOURCES & PRIORITY

   - SetUserFTA: Tool that calculates UserChoice hash
   - Windows Registry: UserChoice keys for protocols/extensions

 REQUIRED INPUTS

   All inputs are hardcoded in the script body (booleans, $true/$false):

   Associations:
     - $setDefaultHttp: Set Chrome as default for http:// links
     - $setDefaultHttps: Set Chrome as default for https:// links
     - $setDefaultHtm: Set Chrome as default for .htm files
     - $setDefaultHtml: Set Chrome as default for .html files

   Maintenance:
     - $cleanUserStartup: Remove Edge from user's startup programs

   Tool Configuration:
     - $setUserFtaUrl: URL to download SetUserFTA (hosted in this repo)

 SETTINGS

   All options default to $true. SetUserFTA is hosted in the limehawk
   rmm-scripts repo. Change the URL if you host it elsewhere.

 BEHAVIOR

   The script performs the following actions in order:
   1. Verifies Chrome is installed
   2. Checks that script is NOT running as SYSTEM
   3. Downloads SetUserFTA if not present
   4. Sets Chrome as default for http, https, .htm, .html

 PREREQUISITES

   - PowerShell 5.1 or later
   - Must run as logged-in user (NOT as SYSTEM)
   - Google Chrome must be installed
   - Internet access (to download SetUserFTA if needed)

 SECURITY NOTES

   - No secrets exposed in output
   - SetUserFTA downloaded from limehawk repo
   - Only modifies current user's default app associations
   - No admin rights required

 ENDPOINTS

   - https://github.com/limehawk/rmm-scripts - SetUserFTA download

 EXIT CODES

   0 = Success
   1 = Failure (error occurred)

 EXAMPLE RUN

   [ USER CHECK ]
   --------------------------------------------------------------
   Running as : DOMAIN\jsmith
   Context is valid (not SYSTEM)

   [ CHROME CHECK ]
   --------------------------------------------------------------
   Chrome found : C:\Program Files\Google\Chrome\Application\chrome.exe

   [ SETUP SETUSERFTA ]
   --------------------------------------------------------------
   Downloading SetUserFTA...
   Downloaded SetUserFTA

   [ SET CHROME DEFAULT ]
   --------------------------------------------------------------
   Set Chrome as default for http
   Set Chrome as default for https
   Set Chrome as default for .htm
   Set Chrome as default for .html

   [ FINAL STATUS ]
   --------------------------------------------------------------
   Result : SUCCESS
   Chrome is now the default browser

   [ SCRIPT COMPLETE ]
   --------------------------------------------------------------

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2024-12-27 v1.2.0 Host SetUserFTA in limehawk repo, remove external dependency
 2024-12-27 v1.1.0 Added boolean settings at top for each feature
 2024-12-27 v1.0.0 Initial release - split from combined script
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# SETTINGS - Set to $false to skip specific associations
# ============================================================================

# Associations - which file types/protocols to set Chrome as default
$setDefaultHttp  = $true  # Set Chrome as default for http:// links
$setDefaultHttps = $true  # Set Chrome as default for https:// links
$setDefaultHtm   = $true  # Set Chrome as default for .htm files
$setDefaultHtml  = $true  # Set Chrome as default for .html files

# Maintenance
$cleanUserStartup = $true  # Remove Edge from user's startup programs

# Tool Configuration - SetUserFTA hosted in limehawk repo
$setUserFtaUrl = 'https://github.com/limehawk/rmm-scripts/raw/main/tools/SetUserFTA/SetUserFTA.exe'

# ============================================================================
# STATE VARIABLES
# ============================================================================
$errorOccurred = $false
$errorText = ""
$defaultsSet = 0
$totalAssociations = 0

# ============================================================================
# USER CHECK
# ============================================================================
Write-Host ""
Write-Host "[ USER CHECK ]"
Write-Host "--------------------------------------------------------------"

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Running as : $currentUser"

if ($currentUser -match "SYSTEM$") {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "This script must run as the logged-in user, not SYSTEM"
    Write-Host ""
    Write-Host "Default browser is a per-user setting stored in HKCU."
    Write-Host ""
    Write-Host "Solutions:"
    Write-Host "  - RMM: Run as 'logged-in user' instead of 'SYSTEM'"
    Write-Host "  - GPO: Use a logon script"
    Write-Host "  - Manual: Run from user's PowerShell session"
    exit 1
}
Write-Host "Context is valid (not SYSTEM)"

# ============================================================================
# CHROME CHECK
# ============================================================================
Write-Host ""
Write-Host "[ CHROME CHECK ]"
Write-Host "--------------------------------------------------------------"

$chromePaths = @(
    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:LocalAppData}\Google\Chrome\Application\chrome.exe"
)

$chromePath = $null
foreach ($path in $chromePaths) {
    if (Test-Path $path) {
        $chromePath = $path
        break
    }
}

if (-not $chromePath) {
    Write-Host "ERROR: Chrome is not installed"
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Install Google Chrome before running this script"
    exit 1
}
Write-Host "Chrome found : $chromePath"

# ============================================================================
# SETUP SETUSERFTA
# ============================================================================
Write-Host ""
Write-Host "[ SETUP SETUSERFTA ]"
Write-Host "--------------------------------------------------------------"

$setUserFtaPath = "$env:TEMP\SetUserFTA.exe"

try {
    if (-not (Test-Path $setUserFtaPath)) {
        Write-Host "Downloading SetUserFTA..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $setUserFtaUrl -OutFile $setUserFtaPath -UseBasicParsing
        Write-Host "Downloaded SetUserFTA"
    } else {
        Write-Host "SetUserFTA already present"
    }

    if (-not (Test-Path $setUserFtaPath)) {
        throw "SetUserFTA not found after download"
    }

} catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Failed to download SetUserFTA: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "SetUserFTA is required because Windows 10/11 uses hash"
    Write-Host "validation on UserChoice registry keys. Without the correct"
    Write-Host "hash, Windows ignores registry changes to default apps."
    exit 1
}

# ============================================================================
# SET CHROME DEFAULT
# ============================================================================
Write-Host ""
Write-Host "[ SET CHROME DEFAULT ]"
Write-Host "--------------------------------------------------------------"

$chromeProgId = "ChromeHTML"

if ($setDefaultHttp) {
    $totalAssociations++
    try {
        $result = & $setUserFtaPath "http" $chromeProgId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Set Chrome as default for http"
            $defaultsSet++
        } else {
            Write-Host "Failed to set http: $result"
            $errorOccurred = $true
            if ($errorText.Length -gt 0) { $errorText += "`n" }
            $errorText += "- Could not set http"
        }
    } catch {
        Write-Host "Error setting http: $($_.Exception.Message)"
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Exception on http"
    }
}

if ($setDefaultHttps) {
    $totalAssociations++
    try {
        $result = & $setUserFtaPath "https" $chromeProgId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Set Chrome as default for https"
            $defaultsSet++
        } else {
            Write-Host "Failed to set https: $result"
            $errorOccurred = $true
            if ($errorText.Length -gt 0) { $errorText += "`n" }
            $errorText += "- Could not set https"
        }
    } catch {
        Write-Host "Error setting https: $($_.Exception.Message)"
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Exception on https"
    }
}

if ($setDefaultHtm) {
    $totalAssociations++
    try {
        $result = & $setUserFtaPath ".htm" $chromeProgId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Set Chrome as default for .htm"
            $defaultsSet++
        } else {
            Write-Host "Failed to set .htm: $result"
            $errorOccurred = $true
            if ($errorText.Length -gt 0) { $errorText += "`n" }
            $errorText += "- Could not set .htm"
        }
    } catch {
        Write-Host "Error setting .htm: $($_.Exception.Message)"
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Exception on .htm"
    }
}

if ($setDefaultHtml) {
    $totalAssociations++
    try {
        $result = & $setUserFtaPath ".html" $chromeProgId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Set Chrome as default for .html"
            $defaultsSet++
        } else {
            Write-Host "Failed to set .html: $result"
            $errorOccurred = $true
            if ($errorText.Length -gt 0) { $errorText += "`n" }
            $errorText += "- Could not set .html"
        }
    } catch {
        Write-Host "Error setting .html: $($_.Exception.Message)"
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Exception on .html"
    }
}

# ============================================================================
# CLEANUP USER EDGE STARTUP
# ============================================================================
if ($cleanUserStartup) {
    Write-Host ""
    Write-Host "[ USER CLEANUP ]"
    Write-Host "--------------------------------------------------------------"

    try {
        $userRunPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $userRunPath) {
            $properties = Get-ItemProperty -Path $userRunPath -ErrorAction SilentlyContinue
            if ($properties) {
                $edgeEntries = $properties.PSObject.Properties | Where-Object { $_.Name -like "*Edge*" -or $_.Name -like "*MicrosoftEdge*" }
                if ($edgeEntries) {
                    foreach ($entry in $edgeEntries) {
                        Remove-ItemProperty -Path $userRunPath -Name $entry.Name -Force -ErrorAction SilentlyContinue
                        Write-Host "Removed user startup : $($entry.Name)"
                    }
                } else {
                    Write-Host "No Edge user startup entries"
                }
            }
        }
    } catch {
        Write-Host "Cleanup skipped: $($_.Exception.Message)"
    }
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

if ($defaultsSet -eq 0) {
    Write-Host "Result : FAILED"
    Write-Host "No defaults were set"
    if ($errorText.Length -gt 0) {
        Write-Host ""
        Write-Host "Errors:"
        Write-Host $errorText
    }
    Write-Host ""
    Write-Host "[ SCRIPT COMPLETE ]"
    Write-Host "--------------------------------------------------------------"
    exit 1
}

if ($errorOccurred) {
    Write-Host "Result : PARTIAL SUCCESS"
    Write-Host "Defaults set : $defaultsSet of $totalAssociations"
    Write-Host ""
    Write-Host "Warnings:"
    Write-Host $errorText
} else {
    Write-Host "Result : SUCCESS"
    Write-Host "Defaults set : $defaultsSet of $totalAssociations"
    Write-Host ""
    Write-Host "Chrome is now the default browser for this user"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETE ]"
Write-Host "--------------------------------------------------------------"
exit 0
