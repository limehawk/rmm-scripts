$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝

================================================================================
SCRIPT : Windows 11 Compatibility Check                                  v1.0.0
FILE   : win11_compatibility_check.ps1
================================================================================
README
--------------------------------------------------------------------------------
PURPOSE:
    Checks if the current Windows device meets the hardware requirements for
    Windows 11 upgrade, including:
    - Processor (2+ cores, 1GHz+)
    - RAM (4GB+)
    - Storage (64GB+)
    - TPM 2.0
    - Secure Boot capability
    - UEFI firmware

REQUIRED INPUTS:
    None

BEHAVIOR:
    1. Checks processor specifications
    2. Checks RAM capacity
    3. Checks disk space
    4. Checks TPM version
    5. Checks Secure Boot status
    6. Reports overall compatibility

PREREQUISITES:
    - Windows 10
    - Administrator privileges (for TPM check)

SECURITY NOTES:
    - No secrets in logs
    - Read-only system checks

EXIT CODES:
    0 = Compatible with Windows 11
    1 = Not compatible with Windows 11

EXAMPLE RUN:
    [ PROCESSOR CHECK ]
    --------------------------------------------------------------
    Processor            : Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz
    Cores                : 8
    Cores Compatible     : Yes

    [ MEMORY CHECK ]
    --------------------------------------------------------------
    Total RAM            : 16 GB
    RAM Compatible       : Yes

    [ STORAGE CHECK ]
    --------------------------------------------------------------
    System Disk Size     : 512 GB
    Storage Compatible   : Yes

    [ TPM CHECK ]
    --------------------------------------------------------------
    TPM Present          : Yes
    TPM Version          : 2.0
    TPM Compatible       : Yes

    [ SECURE BOOT CHECK ]
    --------------------------------------------------------------
    Secure Boot Available: Yes
    Secure Boot Enabled  : Yes

    [ FINAL STATUS ]
    --------------------------------------------------------------
    Windows 11 Compatible: YES
    SCRIPT SUCCEEDED

    [ SCRIPT COMPLETED ]
    --------------------------------------------------------------

CHANGELOG
--------------------------------------------------------------------------------
2024-12-01 v1.0.0  Initial release - migrated from SuperOps (removed module dependency)
================================================================================
#>
Set-StrictMode -Version Latest

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-Section {
    param([string]$title)
    Write-Host ""
    Write-Host ("[ {0} ]" -f $title)
    Write-Host ("-" * 62)
}

function PrintKV([string]$label, [string]$value) {
    $lbl = $label.PadRight(24)
    Write-Host (" {0} : {1}" -f $lbl, $value)
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
try {
    $IsCompatible = $true
    $issues = @()

    # Processor Check
    Write-Section "PROCESSOR CHECK"

    $Processor = Get-WmiObject -Class Win32_Processor
    $ProcessorName = $Processor.Name
    $ProcessorCoreCount = $Processor.NumberOfCores
    $ProcessorSpeed = [math]::Round($Processor.MaxClockSpeed / 1000, 2)

    PrintKV "Processor" $ProcessorName
    PrintKV "Cores" $ProcessorCoreCount
    PrintKV "Speed (GHz)" $ProcessorSpeed

    $ProcessorCoresCompatible = $ProcessorCoreCount -ge 2
    $ProcessorSpeedCompatible = $ProcessorSpeed -ge 1.0

    PrintKV "Cores Compatible" $(if ($ProcessorCoresCompatible) { "Yes" } else { "No (need 2+)" })
    PrintKV "Speed Compatible" $(if ($ProcessorSpeedCompatible) { "Yes" } else { "No (need 1GHz+)" })

    if (-not $ProcessorCoresCompatible) {
        $IsCompatible = $false
        $issues += "Processor needs 2+ cores"
    }
    if (-not $ProcessorSpeedCompatible) {
        $IsCompatible = $false
        $issues += "Processor needs 1GHz+ speed"
    }

    # Memory Check
    Write-Section "MEMORY CHECK"

    $RAM = [math]::Round((Get-WmiObject -Class Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB, 1)
    $RAMCompatible = $RAM -ge 4

    PrintKV "Total RAM" "$RAM GB"
    PrintKV "RAM Compatible" $(if ($RAMCompatible) { "Yes" } else { "No (need 4GB+)" })

    if (-not $RAMCompatible) {
        $IsCompatible = $false
        $issues += "Needs 4GB+ RAM"
    }

    # Storage Check
    Write-Section "STORAGE CHECK"

    $Disk = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
    $DiskSize = [math]::Round($Disk.Size / 1GB, 0)
    $DiskCompatible = $DiskSize -ge 64

    PrintKV "System Disk Size" "$DiskSize GB"
    PrintKV "Storage Compatible" $(if ($DiskCompatible) { "Yes" } else { "No (need 64GB+)" })

    if (-not $DiskCompatible) {
        $IsCompatible = $false
        $issues += "Needs 64GB+ storage"
    }

    # TPM Check
    Write-Section "TPM CHECK"

    $TPMCompatible = $false
    try {
        $TPM = Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction Stop

        if ($TPM) {
            $TPMPresent = $true
            $TPMVersion = $TPM.SpecVersion
            $TPMVersionNum = if ($TPMVersion -match "^(\d+\.\d+)") { [version]$Matches[1] } else { [version]"0.0" }
            $TPMCompatible = $TPMVersionNum -ge [version]"2.0"

            PrintKV "TPM Present" "Yes"
            PrintKV "TPM Version" $TPMVersion
            PrintKV "TPM Compatible" $(if ($TPMCompatible) { "Yes" } else { "No (need 2.0+)" })
        } else {
            PrintKV "TPM Present" "No"
            PrintKV "TPM Compatible" "No (not found)"
        }
    } catch {
        PrintKV "TPM Present" "Unknown (access denied)"
        PrintKV "TPM Compatible" "Unable to verify"
    }

    if (-not $TPMCompatible) {
        $IsCompatible = $false
        $issues += "Needs TPM 2.0"
    }

    # Secure Boot Check
    Write-Section "SECURE BOOT CHECK"

    $SecureBootAvailable = $false
    $SecureBootEnabled = $false

    try {
        $SecureBoot = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -ErrorAction Stop
        $SecureBootAvailable = $true
        $SecureBootEnabled = $SecureBoot.UEFISecureBootEnabled -eq 1
    } catch {
        $SecureBootAvailable = $false
    }

    PrintKV "Secure Boot Available" $(if ($SecureBootAvailable) { "Yes" } else { "No" })
    PrintKV "Secure Boot Enabled" $(if ($SecureBootEnabled) { "Yes" } else { "No" })

    if (-not $SecureBootAvailable) {
        Write-Host ""
        Write-Host " Note: Secure Boot is recommended but may be available in BIOS."
    } elseif (-not $SecureBootEnabled) {
        Write-Host ""
        Write-Host " Note: Secure Boot is available but currently disabled."
        Write-Host " Consider enabling it in BIOS for enhanced security."
    }

    # UEFI Check
    Write-Section "FIRMWARE CHECK"

    $FirmwareType = "Unknown"
    try {
        $firmware = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction SilentlyContinue
        if ($firmware) {
            $FirmwareType = "UEFI"
        } else {
            # Check via bcdedit
            $bcdedit = bcdedit /enum | Select-String "path.*efi"
            if ($bcdedit) {
                $FirmwareType = "UEFI"
            } else {
                $FirmwareType = "Legacy BIOS"
            }
        }
    } catch {
        $FirmwareType = "Unknown"
    }

    PrintKV "Firmware Type" $FirmwareType
    PrintKV "UEFI Compatible" $(if ($FirmwareType -eq "UEFI") { "Yes" } else { "No (need UEFI)" })

    if ($FirmwareType -ne "UEFI") {
        $IsCompatible = $false
        $issues += "Needs UEFI firmware"
    }

    # Final Status
    Write-Section "FINAL STATUS"

    if ($IsCompatible) {
        PrintKV "Windows 11 Compatible" "YES"
        Write-Host " SCRIPT SUCCEEDED"
        Write-Host ""
        Write-Host " This device meets Windows 11 hardware requirements."
    } else {
        PrintKV "Windows 11 Compatible" "NO"
        Write-Host ""
        Write-Host " Issues Found:"
        foreach ($issue in $issues) {
            Write-Host "  - $issue"
        }
    }

    Write-Section "SCRIPT COMPLETED"

    if ($IsCompatible) {
        exit 0
    } else {
        exit 1
    }
}
catch {
    Write-Section "ERROR OCCURRED"
    PrintKV "Error Message" $_.Exception.Message
    PrintKV "Error Type" $_.Exception.GetType().FullName
    Write-Section "SCRIPT HALTED"
    exit 1
}
