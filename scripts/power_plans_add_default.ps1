$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Add Default Power Plans                                        v1.0.0
FILE   : power_plans_add_default.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Adds the four standard Windows power plans (High Performance, Ultimate
    Performance, Power Saver, and Balanced) by duplicating them from their
    default GUIDs. Useful for restoring missing power plans on systems where
    they have been removed or are unavailable.

REQUIRED INPUTS:
    None - uses standard Windows power plan GUIDs

BEHAVIOR:
    1. Duplicates High Performance power plan
    2. Duplicates Ultimate Performance power plan (Win10 1803+)
    3. Duplicates Power Saver power plan
    4. Duplicates Balanced power plan
    5. Reports success/failure for each plan

PREREQUISITES:
    - Windows 10/11 or Windows Server 2016+
    - Administrator privileges
    - powercfg.exe available (standard Windows component)

SECURITY NOTES:
    - No secrets in logs
    - Uses standard Windows power plan GUIDs

EXIT CODES:
    0 = Success (all plans added)
    1 = Failure

EXAMPLE RUN:
    [ INPUT VALIDATION ]
    --------------------------------------------------------------
    No inputs required

    [ ADDING POWER PLANS ]
    --------------------------------------------------------------
    High Performance     : Added successfully
    Ultimate Performance : Added successfully
    Power Saver          : Added successfully
    Balanced             : Added successfully

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Result : SUCCESS
    All power plans added successfully

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - converted from batch script
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HARDCODED INPUTS
# ============================================================================
# Standard Windows power plan GUIDs
$powerPlans = @{
    'High Performance'     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    'Ultimate Performance' = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    'Power Saver'          = 'a1841308-3541-4fab-bc81-f71556f20b4a'
    'Balanced'             = '381b4222-f694-41f0-9685-ff5bb260df2e'
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================
Write-Host ""
Write-Host "[ INPUT VALIDATION ]"
Write-Host "--------------------------------------------------------------"
Write-Host "No inputs required"

# ============================================================================
# ADD POWER PLANS
# ============================================================================
Write-Host ""
Write-Host "[ ADDING POWER PLANS ]"
Write-Host "--------------------------------------------------------------"

$errorOccurred = $false
$errorText = ""

foreach ($planName in $powerPlans.Keys) {
    $planGuid = $powerPlans[$planName]
    $label = $planName.PadRight(20)

    try {
        $output = powercfg -duplicatescheme $planGuid 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$label : Added successfully"
        }
        elseif ($output -match 'already exists') {
            Write-Host "$label : Already exists"
        }
        else {
            Write-Host "$label : Failed - $output"
            $errorOccurred = $true
            if ($errorText.Length -gt 0) { $errorText += "`n" }
            $errorText += "- Failed to add $planName"
        }
    }
    catch {
        Write-Host "$label : Error - $($_.Exception.Message)"
        $errorOccurred = $true
        if ($errorText.Length -gt 0) { $errorText += "`n" }
        $errorText += "- Error adding $planName : $($_.Exception.Message)"
    }
}

# ============================================================================
# ERROR HANDLING
# ============================================================================
if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host $errorText
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"

if ($errorOccurred) {
    Write-Host "Result : FAILURE"
    Write-Host "Some power plans could not be added"
    exit 1
}
else {
    Write-Host "Result : SUCCESS"
    Write-Host "All power plans added successfully"
}

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
