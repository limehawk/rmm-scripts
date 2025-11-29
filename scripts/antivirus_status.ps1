# Import the SuperOps module (provided by RMM)
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
 SCRIPT    : antivirus_status.ps1
 VERSION   : v1.2.0
================================================================================
 FILE      : antivirus_status.ps1
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
 Checks for the presence and active status of third-party antivirus software on
 the system, excluding Windows/Microsoft Defender. Reports the active product
 name and boolean state to SuperOps custom fields for monitoring.

 DATA SOURCES & PRIORITY
 1) Hardcoded values (defined within the script body)
 2) CIM instance query to root\SecurityCenter2\AntiVirusProduct for third-party AV
 3) Registry fallback if SecurityCenter2 is unavailable
 4) Get-MpComputerStatus for Windows Defender confirmation (informational only)

 REQUIRED INPUTS
 - $SuperOpsModule: Path to SuperOps module (injected by RMM; validated as non-empty string).

 SETTINGS
 - None configurable; all logic is fixed for third-party AV detection.

 BEHAVIOR
 - Queries installed AV products and checks enabled state via productState bitmask.
 - Falls back to registry detection if WMI/CIM fails.
 - Ignores Windows Defender entries.
 - Outputs third-party AV name (or detection message) and state (TRUE/FALSE).
 - Separately confirms Windows Defender status in console output.
 - Pushes results to SuperOps custom fields: "Active Antivirus" (string) and
   "Active Antivirus State" (TRUE/FALSE for radio buttons).
 - On error, defaults state to FALSE and reports detection error.

 PREREQUISITES
 - PowerShell 5.1 or later.
 - Access to root\SecurityCenter2 namespace (requires local admin or equivalent).
 - SuperOps module available via $SuperOpsModule variable (provided by RMM).

 SECURITY NOTES
 - No secrets (API keys, passwords) are used or logged.
 - Queries only local system data; no network calls.

 ENDPOINTS
 - N/A

 EXIT CODES
 - 0 success
 - 1 failure

 EXAMPLE RUN (Style A)
 [ INPUT VALIDATION ]
 --------------------------------------------------------------
 SuperOpsModule : C:\Program Files\SuperOps\Modules\SuperOps.psm1

 [ OPERATION ]
 --------------------------------------------------------------
 Querying AntiVirusProduct...
 Checking Windows Defender...

 [ RESULT ]
 --------------------------------------------------------------
 Active Antivirus : No Active Third-Party Antivirus Detected
 Active Antivirus State : FALSE
 Windows Defender Enabled : True

 [ FINAL STATUS ]
 --------------------------------------------------------------
 Third-party AV check completed successfully.

 [ SCRIPT COMPLETED ]
 --------------------------------------------------------------
 --------------------------------------------------------------------------------
 CHANGELOG
 2025-10-28 v1.2.0 Added registry fallback, WMI service checks, and better error handling
                   for SecurityCenter2 provider failures.
 2025-10-28 v1.1.0 Improved AV detection with better productState logic, OS type
                   checking, enhanced Defender filtering, and comprehensive logging.
 2025-10-27 v1.0.0 Initial version with third-party AV focus and SuperOps integration.
================================================================================
#>

Set-StrictMode -Version Latest

# ==== STATE (NO ARRAYS/LISTS) ====
$errorOccurred = $false
$errorText     = ""   # Accumulate newline-delimited messages.

# ==== HARDCODED INPUTS (MANDATORY) ====
# Relies on $SuperOpsModule injected by RMM.

# ==== VALIDATION ====
if ([string]::IsNullOrWhiteSpace($SuperOpsModule)) {
    $errorOccurred = $true
    $errorText += "- SuperOpsModule path is required (injected by RMM)."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

# ==== RUNTIME OUTPUT (Style A) ====
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"
Write-Host "SuperOpsModule : $SuperOpsModule"

Write-Host ""
Write-Host "[ OPERATION ]"
Write-Host "--------------------------------------------------------------"

# ==== HELPER FUNCTION: Registry-based AV Detection ====
function Get-AVFromRegistry {
    Write-Host "Attempting registry-based AV detection..."
    $avFound = ""
    $avActive = $false
    
    # Common AV registry locations
    $avPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    # Known AV product patterns (excluding Microsoft)
    $avPatterns = @(
        "Norton", "Symantec", "McAfee", "Kaspersky", "Bitdefender",
        "Avast", "AVG", "Trend Micro", "ESET", "Sophos",
        "Malwarebytes", "Webroot", "F-Secure", "Panda",
        "Avira", "Comodo", "ZoneAlarm", "BullGuard", "G Data",
        "Emsisoft", "Vipre", "Sentinel", "CrowdStrike", "Carbon Black"
    )
    
    foreach ($path in $avPaths) {
        try {
            $installed = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -and $_.DisplayName -notmatch "^(Windows|Microsoft)\s+(Defender|Security)"
            }
            
            foreach ($app in $installed) {
                foreach ($pattern in $avPatterns) {
                    if ($app.DisplayName -match $pattern) {
                        Write-Host "  Found in registry: $($app.DisplayName)"
                        if ($avFound.Length -gt 0) { $avFound += ", " }
                        $avFound += $app.DisplayName
                        $avActive = $true
                    }
                }
            }
        } catch {
            Write-Host "  Registry path failed: $path"
        }
    }
    
    return @{
        Name = $avFound
        Active = $avActive
    }
}

try {
    # Check OS type first (SecurityCenter2 only exists on client OS)
    Write-Host "Checking OS type..."
    $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $isServerOS = $OSInfo.ProductType -ne 1  # 1 = Workstation, 2 = Domain Controller, 3 = Server
    
    if ($isServerOS) {
        Write-Host "Server OS detected - SecurityCenter2 namespace not available"
        Write-Host "Attempting alternative detection methods..."
        
        $regResult = Get-AVFromRegistry
        
        if ($regResult.Active) {
            $ActiveAV = $regResult.Name
            $AVStatus = $true
        } else {
            $ActiveAV = "Server OS - No Third-Party AV Detected"
            $AVStatus = $false
        }
        
        # Still check Windows Defender on servers
        try {
            $DefenderStatus = Get-MpComputerStatus -ErrorAction Stop
            Write-Host "Windows Defender Status: Enabled=$($DefenderStatus.AntivirusEnabled), RealTime=$($DefenderStatus.RealTimeProtectionEnabled)"
        } catch {
            Write-Host "Windows Defender check failed: $($_.Exception.Message)"
            $DefenderStatus = $null
        }
    } else {
        Write-Host "Client OS detected"
        
        # Check if WMI/SecurityCenter service is running
        Write-Host "Checking SecurityCenter service..."
        $secCenter = Get-Service -Name "wscsvc" -ErrorAction SilentlyContinue
        if ($secCenter -and $secCenter.Status -ne "Running") {
            Write-Host "WARNING: SecurityCenter service (wscsvc) is not running. Status: $($secCenter.Status)"
            Write-Host "Attempting to start service..."
            try {
                Start-Service -Name "wscsvc" -ErrorAction Stop
                Start-Sleep -Seconds 2
                Write-Host "Service started successfully"
            } catch {
                Write-Host "Failed to start SecurityCenter service: $($_.Exception.Message)"
            }
        }
        
        # Try SecurityCenter2 query with better error handling
        $AntivirusProducts = $null
        $secCenter2Failed = $false
        
        Write-Host "Querying AntiVirusProduct via SecurityCenter2..."
        try {
            # Test namespace existence first
            $null = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "__Namespace" -ErrorAction Stop
            
            # Now query AV products
            $AntivirusProducts = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction Stop
            Write-Host "SecurityCenter2 query successful"
        } catch {
            $secCenter2Failed = $true
            Write-Host "SecurityCenter2 query failed: $($_.Exception.Message)"
            Write-Host "Falling back to registry detection..."
        }

        Write-Host "Checking Windows Defender..."
        try {
            $DefenderStatus = Get-MpComputerStatus -ErrorAction Stop
        } catch {
            Write-Host "Windows Defender check failed: $($_.Exception.Message)"
            $DefenderStatus = $null
        }

        $ActiveAV = "No Active Third-Party Antivirus Detected"
        $AVStatus = $false  # Boolean: false for inactive third-party AV
        $activeAVNames = ""  # Accumulate comma-separated names

        # Process SecurityCenter2 results if available
        if (-not $secCenter2Failed -and $AntivirusProducts) {
            Write-Host ""
            Write-Host "[ DIAGNOSTIC: All AV Products Found ]"
            Write-Host "--------------------------------------------------------------"
            
            foreach ($av in $AntivirusProducts) {
                $hexState = "0x{0:X6}" -f $av.productState
                $isEnabled = ($av.productState -band 0x1000) -ne 0
                $defStatus = $av.productState -band 0x00FF
                
                Write-Host "Product: $($av.displayName)"
                Write-Host "  State: $hexState | Enabled: $isEnabled | DefBits: 0x$("{0:X2}" -f $defStatus)"
                Write-Host "  Path: $($av.pathToSignedProductExe)"
                Write-Host ""
            }
            Write-Host "--------------------------------------------------------------"
            Write-Host ""

            # Check for active third-party AV
            foreach ($av in $AntivirusProducts) {
                # More specific Defender exclusion using regex
                if ($av.displayName -match "^(Windows|Microsoft)\s+(Defender|Security)") {
                    Write-Host "Skipping Microsoft product: $($av.displayName)"
                    continue
                }
                
                # Enhanced productState check
                $isEnabled = ($av.productState -band 0x1000) -ne 0
                
                if ($isEnabled) {
                    Write-Host "ACTIVE third-party AV found: $($av.displayName)"
                    
                    if ($activeAVNames.Length -gt 0) {
                        $activeAVNames += ", "
                    }
                    $activeAVNames += $av.displayName
                    $AVStatus = $true
                }
            }

            # Set final value
            if ($AVStatus) {
                $ActiveAV = $activeAVNames
            }
        } elseif ($secCenter2Failed) {
            # Fallback to registry if SecurityCenter2 failed
            $regResult = Get-AVFromRegistry
            
            if ($regResult.Active) {
                $ActiveAV = $regResult.Name
                $AVStatus = $true
                Write-Host "Registry detection found: $ActiveAV"
            } else {
                $ActiveAV = "SecurityCenter2 Unavailable - No AV Found in Registry"
                $AVStatus = $false
            }
        } else {
            Write-Host "No AV products found in SecurityCenter2"
        }
    }

    # Push to SuperOps custom fields (third-party focused)
    Send-CustomField -CustomFieldName "Active Antivirus" -Value $ActiveAV  # String: third-party product name or detection message
    Send-CustomField -CustomFieldName "Active Antivirus State" -Value $AVStatus.ToString().ToUpper()  # "TRUE" or "FALSE" for radio buttons
} catch {
    $errorOccurred = $true
    $ErrorMsg = "Error checking AV status: $($_.Exception.Message)"
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += $ErrorMsg

    # Push error defaults to SuperOps
    Send-CustomField -CustomFieldName "Active Antivirus" -Value "Error: Unable to detect" -ErrorAction SilentlyContinue
    Send-CustomField -CustomFieldName "Active Antivirus State" -Value "FALSE" -ErrorAction SilentlyContinue
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
    exit 1
}

Write-Host ""
Write-Host "[ RESULT ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Active Antivirus : $ActiveAV"
Write-Host "Active Antivirus State : $($AVStatus.ToString().ToUpper())"
if ($DefenderStatus) {
    Write-Host "Windows Defender Enabled : $($DefenderStatus.AntivirusEnabled)"
    Write-Host "Windows Defender RealTime : $($DefenderStatus.RealTimeProtectionEnabled)"
}

Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Third-party AV check completed successfully."

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"
exit 0