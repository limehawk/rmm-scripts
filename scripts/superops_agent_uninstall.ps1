$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : SuperOps Agent Uninstall                                      v2.0.0
 AUTHOR   : Limehawk.io
 DATE     : August 2026
 USAGE    : .\superops_agent_uninstall.ps1
================================================================================
 FILE     : superops_agent_uninstall.ps1
 DESCRIPTION : Uninstalls SuperOps/Limehawk RMM agent and leftover remnants
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE

   Removes the SuperOps RMM agent (including Limehawk-branded installs) from
   Windows. Tamper protection can leave the service and files after MSI
   reports success, so the service is deleted first, msiexec is watched for
   hangs, and leftovers are verified before exit. Missing product is success
   so the script is safe to re-run.

 DATA SOURCES & PRIORITY

   1) Hardcoded SuperOps MSI ProductCode GUID
   2) Win32_Service ImagePath (*limehawkrmm* / *superops.exe*) and name limehawk
   3) Uninstall registry (DisplayName Limehawk*/SuperOps*, publisher SuperOps)
   4) msiexec /x with hang timeout, then leftover file/registry cleanup

 REQUIRED INPUTS

   All inputs are hardcoded in the script body:
     - $ProductGuid : SuperOps agent MSI IdentifyingNumber

 SETTINGS

   - Silent MSI args : /qn /norestart
   - msiexec hang timeout : 90 seconds (near-zero CPU = hung, then taskkill)
   - msiexec exit 0 is not proof the agent is gone
   - Service match is name/display limehawk* / superops*, or ImagePath
   - Already-removed agent is exit 0

 BEHAVIOR

   1. Confirms administrator privileges
   2. Discovers services (ImagePath / name limehawk) and product codes
   3. sc stop + sc delete FIRST (works with tamper on)
   4. Kills agent and self-heal processes
   5. msiexec /x for each product code; kills hung or idle msiexec
   6. Kills leftovers again, removes limehawkrmm / SuperOps dirs and keys
   7. Verifies service 1060, no limehawkrmm processes, dirs gone

 PREREQUISITES

   - PowerShell 5.1 or later
   - Administrator privileges
   - Windows

 SECURITY NOTES

   - No secrets in logs
   - No network calls
   - Does not touch Limehawk user profiles or branding pictures

 ENDPOINTS

   - Not applicable (local OS operations only)

 EXIT CODES

   0 = Success (uninstalled, cleaned, or already absent)
   1 = Failure (not admin, remnants remain, or uninstall/cleanup error)

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
     Product GUID     : {3BB93941-0FBF-4E6E-CFC2-01C0FA4F9301}
     Admin Privileges : Confirmed

   [RUN] STOP SERVICES
   ==============================================================
     [RUN] sc stop limehawk
     [RUN] sc delete limehawk
     [OK] sc delete limehawk

   [RUN] UNINSTALL
   ==============================================================
     [RUN] msiexec /x {3BB93941-0FBF-4E6E-CFC2-01C0FA4F9301}
     [WARN] msiexec hung (timeout 90s) - killing
     [RUN] Force leftover cleanup

   [RUN] LEFTOVER CLEANUP
   ==============================================================
     [OK] Service limehawk absent (1060)
     [OK] Removed : C:\Program Files\limehawkrmm

   [OK] FINAL STATUS
   ==============================================================
     Result           : SUCCESS
     SuperOps agent uninstalled

   [OK] SCRIPT COMPLETED
   ==============================================================

--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-08-19 v2.0.0 One Windows uninstaller. Service delete first (tamper),
                   hung msiexec watchdog, Limehawk RMM / limehawkrmm
                   discovery, leftover verify. Folded _alt + legacy.
 2026-08-07 v1.1.2 Fix strict-mode crash in registry fallback
 2026-01-19 v1.1.1 Updated to two-line ASCII console output style
 2025-12-23 v1.1.0 Updated to Limehawk Script Framework
 2025-11-02 v1.0.0 Initial release
================================================================================
#>

# ==============================================================================
# HARDCODED INPUTS
# ==============================================================================

$ProductGuid = '{3BB93941-0FBF-4E6E-CFC2-01C0FA4F9301}'
$SilentMsiArgs = @('/qn', '/norestart')
$MsiHangSeconds = 90
$MsiIdleSeconds = 45
$UninstallRegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$InstallPaths = @(
    "${env:ProgramFiles}\limehawkrmm",
    "${env:ProgramFiles(x86)}\limehawkrmm",
    "${env:ProgramData}\limehawkrmm",
    "${env:ProgramFiles}\SuperOps",
    "${env:ProgramFiles(x86)}\SuperOps",
    "${env:ProgramData}\SuperOps",
    "${env:ProgramFiles}\Limehawkrmmagent",
    "${env:ProgramFiles(x86)}\Limehawkrmmagent",
    "${env:ProgramData}\Limehawkrmmagent"
)
$ServiceNamePattern = '(?i)^(limehawk|limehawkrmm|limehawkagent|limehawkupdater|superops)'
$PathPattern = '(?i)limehawkrmm|\\superops\.exe'
$ProcessNamePattern = '(?i)^(superops|superopssetup|superopssetup_new|superopsticket|updmgr|osupdater)$'

Set-StrictMode -Version Latest

# ==============================================================================
# STATE
# ==============================================================================

$errorOccurred = $false
$errorText = ""
$hadAgent = $false

function Get-Prop([object]$Object, [string]$Name) {
    if ($Object -and $Object.PSObject.Properties[$Name]) {
        return [string]$Object.$Name
    }
    return ''
}

function Get-GuidFromText([string]$Text) {
    if ($Text -match '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}') {
        return $Matches[0].ToUpper()
    }
    return ''
}

function Get-AgentServices {
    @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        ([string]$_.Name -match $ServiceNamePattern) -or
        ([string]$_.DisplayName -match $ServiceNamePattern) -or
        ([string]$_.PathName -match $PathPattern)
    })
}

function Get-AgentProcesses {
    @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $name = ([string]$_.Name) -replace '\.exe$', ''
        $exe = [string]$_.ExecutablePath
        $cmd = [string]$_.CommandLine
        ($exe -match $PathPattern) -or ($cmd -match $PathPattern) -or ($name -match $ProcessNamePattern)
    })
}

function Stop-MsiForGuid([string]$Guid) {
    Get-CimInstance -ClassName Win32_Process -Filter "Name='msiexec.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match [regex]::Escape($Guid) } |
        ForEach-Object {
            Write-Host "[WARN] Killing hung msiexec PID $($_.ProcessId)"
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Remove-AgentServices {
    $services = Get-AgentServices
    if ($services.Count -eq 0) {
        Write-Host "[OK] No agent services"
        return
    }
    $script:hadAgent = $true
    foreach ($svc in $services) {
        Write-Host "[RUN] sc stop $($svc.Name)"
        $null = & sc.exe stop $svc.Name
        Write-Host "[RUN] sc delete $($svc.Name)"
        $null = & sc.exe delete $svc.Name
        Write-Host "[OK] sc delete $($svc.Name) exit $LASTEXITCODE"
    }
}

function Stop-AgentProcesses {
    $procs = Get-AgentProcesses
    if ($procs.Count -eq 0) {
        Write-Host "[OK] No agent processes"
        return
    }
    $script:hadAgent = $true
    foreach ($proc in $procs) {
        Write-Host "[RUN] taskkill $($proc.Name) ($($proc.ProcessId))"
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorOccurred = $true
    $errorText = "This script requires administrator privileges."
}

if ([string]::IsNullOrWhiteSpace($ProductGuid)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Product GUID is required"
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    Write-Host ""
    Write-Host "[ERROR] FINAL STATUS"
    Write-Host "=============================================================="
    Write-Host "Script cannot proceed. See error details above."
    Write-Host ""
    Write-Host "[INFO] SCRIPT COMPLETED"
    Write-Host "=============================================================="
    exit 1
}

Write-Host "  Product GUID     : $ProductGuid"
Write-Host "  Admin Privileges : Confirmed"

# ==============================================================================
# DISCOVER
# ==============================================================================

$productCodes = New-Object System.Collections.Generic.List[string]
$productCodes.Add($ProductGuid.ToUpper())
$registryHits = New-Object System.Collections.Generic.List[string]

foreach ($regPath in $UninstallRegistryPaths) {
    if (-not (Test-Path $regPath)) { continue }
    Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if (-not $props) { return }
        $displayName = Get-Prop $props 'DisplayName'
        $publisher = Get-Prop $props 'Publisher'
        $uninstallString = Get-Prop $props 'UninstallString'
        $guid = Get-GuidFromText $_.PSChildName
        if (-not $guid) { $guid = Get-GuidFromText $uninstallString }
        $isKnownGuid = ($guid -eq $ProductGuid.ToUpper())
        $isAgent = ($displayName -match '(?i)superops|^limehawk') -or ($publisher -match '(?i)^superops')
        if (-not $isKnownGuid -and -not $isAgent) { return }
        $registryHits.Add($_.PSPath)
        $script:hadAgent = $true
        if ($guid -and -not $productCodes.Contains($guid)) {
            $productCodes.Add($guid)
        }
        Write-Host "  Registry hit    : $displayName ($($_.PSChildName))"
    }
}

foreach ($path in $InstallPaths) {
    if (Test-Path -LiteralPath $path) {
        $script:hadAgent = $true
        Write-Host "  Install dir     : $path"
    }
}

# ==============================================================================
# STOP / DELETE SERVICES FIRST (tamper-on)
# ==============================================================================

Write-Host ""
Write-Host "[RUN] STOP SERVICES"
Write-Host "=============================================================="
Remove-AgentServices
Stop-AgentProcesses

# ==============================================================================
# MSI UNINSTALL (do not trust exit 0)
# ==============================================================================

Write-Host ""
Write-Host "[RUN] UNINSTALL"
Write-Host "=============================================================="

try {
    foreach ($guid in $productCodes) {
        Write-Host "[RUN] msiexec /x $guid"
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList (@('/x', $guid) + $SilentMsiArgs) -PassThru -NoNewWindow
        $hardDeadline = (Get-Date).AddSeconds($MsiHangSeconds)
        $idleAfter = (Get-Date).AddSeconds($MsiIdleSeconds)
        $lastCpu = [TimeSpan]::Zero
        try { $lastCpu = $proc.TotalProcessorTime } catch { $lastCpu = [TimeSpan]::Zero }
        while (-not $proc.HasExited -and (Get-Date) -lt $hardDeadline) {
            Start-Sleep -Seconds 5
            $proc.Refresh()
            if ($proc.HasExited) { break }
            $cpu = $lastCpu
            try { $cpu = $proc.TotalProcessorTime } catch { }
            $deltaMs = ($cpu - $lastCpu).TotalMilliseconds
            $lastCpu = $cpu
            if ((Get-Date) -ge $idleAfter -and $deltaMs -lt 50) {
                Write-Host "[WARN] msiexec near-zero CPU after ${MsiIdleSeconds}s - killing"
                break
            }
        }
        if (-not $proc.HasExited) {
            Write-Host "[WARN] msiexec hung - killing parent and GUID-matched children"
            Stop-MsiForGuid $guid
            if (-not $proc.HasExited) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Host "[WARN] msiexec exit $($proc.ExitCode) (not treated as gone)"
        }
        Stop-MsiForGuid $guid
    }
} catch {
    $errorOccurred = $true
    $errorText = "Uninstall failed: $($_.Exception.Message)"
}

# ==============================================================================
# FORCE LEFTOVERS
# ==============================================================================

Write-Host ""
Write-Host "[RUN] LEFTOVER CLEANUP"
Write-Host "=============================================================="

try {
    Remove-AgentServices
    Stop-AgentProcesses

    foreach ($path in $InstallPaths) {
        if (Test-Path -LiteralPath $path) {
            Write-Host "[RUN] Removing $path"
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $path) {
                Write-Host "[WARN] Still present : $path"
            } else {
                Write-Host "[OK] Removed        : $path"
            }
        }
    }

    foreach ($regPath in $registryHits) {
        if (Test-Path -LiteralPath $regPath) {
            Write-Host "[RUN] Removing leftover uninstall key"
            Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($softKey in @(
            'HKLM:\SOFTWARE\SuperOps',
            'HKLM:\SOFTWARE\WOW6432Node\SuperOps'
        )) {
        if (Test-Path -LiteralPath $softKey) {
            Write-Host "[RUN] Removing $softKey"
            Remove-Item -LiteralPath $softKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "Cleanup failed: $($_.Exception.Message)"
}

# ==============================================================================
# VERIFY
# ==============================================================================

Write-Host ""
Write-Host "[INFO] VERIFY"
Write-Host "=============================================================="

$leftoverServices = Get-AgentServices
$leftoverProcs = Get-AgentProcesses
$leftoverDirs = @($InstallPaths | Where-Object { Test-Path -LiteralPath $_ })

$scLimehawk = & sc.exe query limehawk 2>&1 | Out-String
if ($scLimehawk -match '1060') {
    Write-Host "[OK] sc query limehawk : 1060"
} elseif ($scLimehawk -match 'STATE') {
    $errorOccurred = $true
    Write-Host "[ERROR] sc query limehawk still present"
} else {
    Write-Host "[OK] sc query limehawk : absent"
}

if ($leftoverServices.Count -eq 0) {
    Write-Host "[OK] No agent services"
} else {
    $errorOccurred = $true
    foreach ($svc in $leftoverServices) {
        Write-Host "[ERROR] Service still present : $($svc.Name)"
    }
}

if ($leftoverProcs.Count -eq 0) {
    Write-Host "[OK] No limehawkrmm / superops processes"
} else {
    $errorOccurred = $true
    foreach ($proc in $leftoverProcs) {
        Write-Host "[ERROR] Process still present : $($proc.Name) ($($proc.ProcessId))"
    }
}

if ($leftoverDirs.Count -eq 0) {
    Write-Host "[OK] No leftover directories"
} else {
    $errorOccurred = $true
    foreach ($path in $leftoverDirs) {
        Write-Host "[ERROR] Directory still present : $path"
    }
}

# ==============================================================================
# RESULT
# ==============================================================================

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    if ($errorText) { Write-Host $errorText }
    Write-Host "Agent remnants remain. Re-run after closing locked files."
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] FINAL STATUS"
} else {
    Write-Host "[OK] FINAL STATUS"
}
Write-Host "=============================================================="
if ($errorOccurred) {
    Write-Host "  Result           : FAILURE"
    Write-Host "  SuperOps agent uninstallation incomplete."
} elseif ($hadAgent) {
    Write-Host "  Result           : SUCCESS"
    Write-Host "  SuperOps agent uninstalled"
} else {
    Write-Host "  Result           : SUCCESS"
    Write-Host "  SuperOps agent already absent"
}

Write-Host ""
if ($errorOccurred) {
    Write-Host "[ERROR] SCRIPT COMPLETED"
} else {
    Write-Host "[OK] SCRIPT COMPLETED"
}
Write-Host "=============================================================="

if ($errorOccurred) {
    exit 1
} else {
    exit 0
}
