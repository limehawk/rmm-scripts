$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT: Foxit PDF Editor+ Install (MS Store)                          VERSION 1.0
FILE: foxit_pdf_editor_plus_install.ps1
--------------------------------------------------------------------------------
README
--------------------------------------------------------------------------------
PURPOSE
Installs Foxit PDF Editor from Microsoft Store source via winget. The MS Store
version validates licenses server-side, supporting all Foxit subscription types
including PDF Editor+, Suite Pro Teams, and other subscription SKUs.

--------------------------------------------------------------------------------
DATA SOURCES & PRIORITY
1. Microsoft Store via winget (package ID: XPDNZD76FP5JR7)

--------------------------------------------------------------------------------
REQUIRED INPUTS
None - package ID is hardcoded

--------------------------------------------------------------------------------
SETTINGS
- Silent install with automatic agreement acceptance
- Uses msstore source for proper subscription license validation

--------------------------------------------------------------------------------
BEHAVIOR
1. Verifies winget is available
2. Installs Foxit PDF Editor from Microsoft Store source
3. Reports installation result based on exit code

--------------------------------------------------------------------------------
PREREQUISITES
- Windows 10/11 with winget installed
- Administrator/SYSTEM privileges
- Internet connectivity to Microsoft Store

--------------------------------------------------------------------------------
SECURITY NOTES
- No secrets in logs
- User must sign into Foxit account post-install to activate license

--------------------------------------------------------------------------------
EXIT CODES
- 0 : Success
- 1 : Failure (winget not found or installation error)

--------------------------------------------------------------------------------
EXAMPLE RUN
[ SETUP ]
--------------------------------------------------------------
Winget found at C:\Users\admin\AppData\Local\Microsoft\WindowsApps\winget.exe

[ INSTALLATION ]
--------------------------------------------------------------
Package ID : XPDNZD76FP5JR7
Source : msstore
Installing Foxit PDF Editor from Microsoft Store...
Installation completed successfully
Exit Code : 0

[ FINAL STATUS ]
--------------------------------------------------------------
Result : SUCCESS
Foxit PDF Editor installed successfully
User must sign into Foxit account to activate license

[ SCRIPT COMPLETED ]
--------------------------------------------------------------

--------------------------------------------------------------------------------
CHANGELOG
--------------------------------------------------------------------------------
2025-06-15 v1.0 Initial release - MS Store installation method

================================================================================
#>
Set-StrictMode -Version Latest

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================

$PackageId = 'XPDNZD76FP5JR7'
$Source    = 'msstore'

# ==============================================================================
# SETUP
# ==============================================================================

Write-Host ""
Write-Host "[ SETUP ]"
Write-Host "--------------------------------------------------------------"

$wingetPath = $null

try {
    $wingetPath = (Get-Command winget -ErrorAction Stop).Source
    Write-Host "Winget found at $wingetPath"
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Winget not found on this system"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Ensure Windows 10 1809+ or Windows 11"
    Write-Host "- Install App Installer from Microsoft Store"
    Write-Host "- Run as a user context if SYSTEM context fails"
    exit 1
}

# ==============================================================================
# INSTALLATION
# ==============================================================================

Write-Host ""
Write-Host "[ INSTALLATION ]"
Write-Host "--------------------------------------------------------------"

Write-Host "Package ID : $PackageId"
Write-Host "Source : $Source"
Write-Host "Installing Foxit PDF Editor from Microsoft Store..."

try {
    $arguments = @(
        'install'
        $PackageId
        '--source', $Source
        '--silent'
        '--accept-source-agreements'
        '--accept-package-agreements'
    )

    $process = Start-Process -FilePath 'winget' -ArgumentList $arguments -Wait -PassThru -NoNewWindow

    $exitCode = $process.ExitCode
    Write-Host "Exit Code : $exitCode"

    if ($exitCode -eq 0) {
        Write-Host "Installation completed successfully"
    }
    elseif ($exitCode -eq -1978335189) {
        Write-Host "Application is already installed"
    }
    elseif ($exitCode -eq -1978335215) {
        throw "No applicable installer found - msstore source may not be available"
    }
    else {
        throw "Installation failed with exit code: $exitCode"
    }
}
catch {
    Write-Host ""
    Write-Host "[ ERROR OCCURRED ]"
    Write-Host "--------------------------------------------------------------"
    Write-Host "Installation failed"
    Write-Host "Error : $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Troubleshooting:"
    Write-Host "- Verify internet connectivity"
    Write-Host "- Check if msstore source is available (winget source list)"
    Write-Host "- Try running as logged-in user instead of SYSTEM"
    Write-Host "- Manually test: winget install $PackageId --source $Source"
    exit 1
}

# ==============================================================================
# FINAL STATUS
# ==============================================================================

Write-Host ""
Write-Host "[ FINAL STATUS ]"
Write-Host "--------------------------------------------------------------"
Write-Host "Result : SUCCESS"
Write-Host "Foxit PDF Editor installed successfully"
Write-Host "User must sign into Foxit account to activate license"

Write-Host ""
Write-Host "[ SCRIPT COMPLETED ]"
Write-Host "--------------------------------------------------------------"

exit 0
