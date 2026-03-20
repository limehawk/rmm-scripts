$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : File Search via Everything                                  v2.0.0
 AUTHOR   : Limehawk.io
 DATE     : March 2026
 USAGE    : .\file_search_everything.ps1
================================================================================
 FILE     : file_search_everything.ps1
 DESCRIPTION : Searches entire system for files matching a pattern using Everything
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Installs Voidtools Everything via winget, searches for files matching a
   hardcoded pattern, and outputs results. Cleans up after itself if it
   installed Everything.

 DATA SOURCES & PRIORITY

   1) Everything NTFS index (built at runtime)

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $searchTerm : File name pattern to search for (Everything syntax)

 SETTINGS

   - Index Timeout : 60 seconds
   - Search Scope : All NTFS volumes

 BEHAVIOR

   1. Resolves winget (SYSTEM context aware)
   2. Installs Everything via winget if not present
   3. Starts Everything service and waits for index
   4. Searches using Everything CLI and outputs results
   5. Cleans up (stops service, uninstalls if script installed it)

 PREREQUISITES

   - Windows 10 1709+ or Windows 11 (winget required)
   - Administrator privileges
   - NTFS filesystem

 SECURITY NOTES

   - No file contents are read or transmitted
   - Everything runs temporarily and is removed if not pre-existing

 ENDPOINTS

   - Not applicable

 EXIT CODES

   0 = Success
   1 = Failure

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Search Term : landtrust

   [RUN] INSTALL EVERYTHING
   ==============================================================
   [RUN] Installing via winget...
   [OK] Everything installed

   [RUN] FILE SEARCH
   ==============================================================
   Searching for: landtrust
   C:\Users\jsmith\Documents\landtrust_agreement.pdf
   Total Matches : 1

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-03-20 v2.0.0 Simplified rewrite - reduced complexity
 2026-03-20 v1.0.0 Initial release
================================================================================
#>
Set-StrictMode -Version Latest

$searchTerm = 'landtrust'
$indexTimeout = 60
$scriptInstalledEverything = $false
$scriptStartedService = $false

function Write-Section([string]$Type, [string]$Name) {
    $indicators = @{ 'info'='INFO'; 'run'='RUN'; 'ok'='OK'; 'warn'='WARN'; 'error'='ERROR' }
    Write-Host ""
    Write-Host "[$($indicators[$Type])] $Name"
    Write-Host "=============================================================="
}

function Resolve-Winget {
    $isSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    if ($isSystem) {
        $resolved = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
            Sort-Object | Select-Object -Last 1
        if ($resolved) { return $resolved.Path }
    } else {
        $cmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Cleanup {
    $everythingExe = Join-Path $env:ProgramFiles "Everything\Everything.exe"
    if ($script:scriptStartedService -and (Test-Path $everythingExe)) {
        & $everythingExe -stop-service 2>&1 | Out-Null
        & $everythingExe -uninstall-service 2>&1 | Out-Null
    }
    if ($script:scriptInstalledEverything) {
        $wg = Resolve-Winget
        if ($wg) { & $wg uninstall -e --id voidtools.Everything --silent --force 2>&1 | Out-Null }
        @("$env:ProgramFiles\Everything", "$env:ProgramData\Everything") | ForEach-Object {
            if (Test-Path $_) { Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

try {
    # Validate input
    Write-Section 'info' 'INPUT VALIDATION'
    if ([string]::IsNullOrWhiteSpace($searchTerm)) {
        throw "Search term is required"
    }
    Write-Host "  Search Term : $searchTerm"

    # Resolve winget
    $wingetExe = Resolve-Winget
    if (-not $wingetExe) {
        throw "winget is not available. Windows 10 1709+ required."
    }

    # Install Everything if needed
    $everythingExe = Join-Path $env:ProgramFiles "Everything\Everything.exe"
    if (-not (Test-Path $everythingExe)) {
        Write-Section 'run' 'INSTALL EVERYTHING'
        Write-Host "  [RUN] Installing via winget..."
        $output = & $wingetExe install -e --id voidtools.Everything --silent --accept-source-agreements --accept-package-agreements 2>&1
        if ($LASTEXITCODE -ne 0) { throw "winget install failed (exit $LASTEXITCODE): $output" }
        $scriptInstalledEverything = $true
        Write-Host "  [OK] Everything installed"

        if (-not (Test-Path $everythingExe)) {
            throw "Everything.exe not found after install"
        }
    }

    # Start service and build index
    $svc = Get-Service -Name "Everything" -ErrorAction SilentlyContinue
    if (-not ($svc -and $svc.Status -eq 'Running')) {
        Write-Section 'run' 'BUILD INDEX'
        Write-Host "  [RUN] Starting Everything service..."
        & $everythingExe -install-service 2>&1 | Out-Null
        & $everythingExe -start-service 2>&1 | Out-Null
        $scriptStartedService = $true

        Write-Host "  [RUN] Waiting for index..."
        $elapsed = 0
        $ready = $false
        while ($elapsed -lt $indexTimeout) {
            Start-Sleep -Seconds 2
            $elapsed += 2
            $test = & $everythingExe -search "notepad.exe" -no-display 2>&1
            if ($LASTEXITCODE -eq 0 -and $test) { $ready = $true; break }
        }
        if (-not $ready) { throw "Index did not build within $indexTimeout seconds" }
        Write-Host "  [OK] Index ready ($elapsed seconds)"
    }

    # Search
    Write-Section 'run' 'FILE SEARCH'
    Write-Host "  Searching for : $searchTerm"
    $results = & $everythingExe -search $searchTerm -no-display 2>&1
    if ($null -eq $results) { $results = @() }
    if ($results -is [string]) { $results = @($results) }
    $results = $results | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    # Results
    Write-Section 'info' 'SEARCH RESULTS'
    if ($results -and $results.Count -gt 0) {
        foreach ($line in $results) { Write-Host "  $line" }
        Write-Host "  --------------------------------------------------------------"
        Write-Host "  Total Matches : $($results.Count)"
    } else {
        Write-Host "  No files found matching : $searchTerm"
    }

    # Cleanup and exit
    Cleanup
    Write-Section 'ok' 'SCRIPT COMPLETED'
    exit 0
}
catch {
    Write-Section 'error' 'ERROR OCCURRED'
    Write-Host "  $($_.Exception.Message)"
    Cleanup
    exit 1
}
