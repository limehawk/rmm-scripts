$ErrorActionPreference = 'Stop'

<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝ 
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗ 
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
 SCRIPT   : Limehawk Admin Profile Branding v4.2.1
 AUTHOR   : Limehawk.io
 DATE      : August 2026
 USAGE    : .\limehawk_admin_profile_branding.ps1
================================================================================
 FILE     : limehawk_admin_profile_branding.ps1
 DESCRIPTION : Creates and manages MSP admin accounts with Level password slots
--------------------------------------------------------------------------------
 README
--------------------------------------------------------------------------------
 PURPOSE
   Standardized Limehawk MSP automation to:
     1) Rename built-in Administrator (SID *-500) to "hawkadmin" and disable it
     2) Create/update "limehawk" MSP admin account (enabled for daily use)
     3) Generate strong passwords for both, emit Level output slots
     4) Clean up old MSP accounts (m5sadmin, tlitlocal, clientadmin)
     5) Apply account pictures and wallpaper branding

 WINDOWS / RUNTIME REQUIREMENTS
   - PowerShell 5.1+
   - Run as local Administrator (elevated)
   - Local user management available (Server/Client SKUs)

 LEVEL REQUIREMENTS
   - Run via Level (SYSTEM). $SuperOpsModule is not present on Level.
   - Passwords print as {{password_admin=...}} / {{password_msp=...}} in the activity log

 SAFETY / IDEMPOTENCE
   - Built-in admin identified by SID *-500, not by name
   - If limehawk account exists, password is reset (safe for existing clients)
   - Account picture & wallpaper operations are no-throw best-effort

 EXIT CODES
   - 0 = success
   - 1 = failure (see “ERROR OCCURRED” diagnostics)
--------------------------------------------------------------------------------
 CHANGELOG
--------------------------------------------------------------------------------
 2026-08-21 v4.2.1 Remove password-file capture workaround. Passwords stay in the activity log.
 2026-08-21 v4.2.0 Write passwords to %ProgramData%\Limehawk for a follow-up capture script
 2026-08-21 v4.1.2 Write slots as UTF-8 bytes to stdout so Level can parse {{name=value}}
 2026-08-21 v4.1.1 Write slots with Write-Output so Level parses stdout, not Write-Host
 2026-08-21 v4.1.0 Emit password_admin / password_msp slots (same names as Level fields); no leading space on tokens
 2026-08-21 v4.0.2 Set wallpaper on a live HKU SID hive when the user is logged on; do not load NTUSER.DAT in that case
 2026-08-20 v4.0.1 Profile photo path is limehawk_profile.png (Level Files)
 2026-08-20 v4.0.0 Ported to Level.io: drop SuperOps module/Send-CustomField; emit BuiltInAdminPassword and MspAdminPassword output slots
 2026-01-19 v3.2.6 Updated to two-line ASCII console output style
 2025-12-23 v3.2.5 Updated to Limehawk Script Framework
 2025-12-04 v3.2.4 Remove UserSwitch registry fix (didn't help, showed all users)
 2025-12-04 v3.2.2 Fix white line artifact - use dark background color instead of white; 2025-12-04 v3.2.1 Add account labels to branding output for clarity
 2025-12-04 v3.2.0 Change profile photo to .jpg; auto-delete old .png file; 2025-12-03 v3.1.8 Unhide limehawk from login screen if hidden via registry
 2025-12-03 v3.1.7 Clean up settings; 2025-12-03 v3.1.6 Remove re-enable logic for hawkadmin; clear FullName; 2025-12-01 v3.1.5 Fix typo in OldMspAccounts
 2025-12-01 v3.1.4 Fix cleanup section using old admin name after rename; 2025-12-01 v3.1.3 Fix error when limehawk account doesn't exist
 2025-10-31 v3.1.2 Improved wallpaper application; 2025-09-05 v3.1.1 Reordered sections; 2025-08-20 v3.1.0 Standardized sections; 2025-08-19 v3.0.0 Initial combined automation
#>

# Optional strict mode
Set-StrictMode -Version Latest

# ============================== SETTINGS =====================================

# Built-in Administrator (SID *-500) - DISABLED, password stored as backup
$BuiltInAdminNewName       = "hawkadmin"                    # Rename built-in admin to this

# MSP Administrator - ENABLED, used for daily MSP access
$MspAdminName              = "limehawk"                     # MSP admin account name
$MspAdminFullName          = "Limehawk"                     # Display name on login screen

# Branding assets (applied to both accounts)
$PhotoSource               = "$env:PUBLIC\Pictures\limehawk_profile.png"
$WallpaperPath             = "$env:PUBLIC\Pictures\limehawk_wallpaper.png"
$OldPhotoSource            = "$env:PUBLIC\Pictures\limehawk_profile.jpg"  # Legacy jpg to clean up

# Misc
$GeneratedPasswordLength   = 16                             # Password length for both accounts

# =============================================================================
# VALIDATION
# =============================================================================
$errorOccurred = $false
$errorText = ""

if ([string]::IsNullOrWhiteSpace($BuiltInAdminNewName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- BuiltInAdminNewName is required."
}
if ([string]::IsNullOrWhiteSpace($MspAdminName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- MspAdminName is required."
}
if ([string]::IsNullOrWhiteSpace($MspAdminFullName)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- MspAdminFullName is required."
}
if ([string]::IsNullOrWhiteSpace($PhotoSource)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- PhotoSource is required."
}
if ([string]::IsNullOrWhiteSpace($WallpaperPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- WallpaperPath is required."
}
if ($GeneratedPasswordLength -lt 8) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- GeneratedPasswordLength must be at least 8."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] INPUT VALIDATION FAILED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

# =============================================================================
# HELPERS (ASCII formatting, sanitization, etc.)
# =============================================================================
function Write-Section {
    param([string]$Title, [string]$Status = "INFO")
    Write-Host ""
    Write-Host ("[$Status] $Title")
    Write-Host "=============================================================="
}
function PrintKV {
    param([string]$Label,[string]$Value)
    $lbl = $Label.PadRight(28)
    Write-Host (" {0} : {1}" -f $lbl, $Value)
}
$script:SlotHeaderShown = $false
function Write-LevelSlot {
    param([string]$Name, [string]$Value)
    if (-not $script:SlotHeaderShown) {
        Write-Host ""
        Write-Host "[INFO] LEVEL OUTPUT SLOTS"
        Write-Host "=============================================================="
        $script:SlotHeaderShown = $true
    }
    $open = [string][char]123 + [string][char]123
    $close = [string][char]125 + [string][char]125
    Write-Host ($open + $Name + '=' + $Value + $close)
}
function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
function New-RandomPassword {
    param([int]$Length=16)

    $lower = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $number = '0123456789'.ToCharArray()
    $symbol = '!@#*-_+'.ToCharArray()

    $allChars = $lower + $upper + $number + $symbol

    $password = ""
    $password += $lower | Get-Random -Count 1
    $password += $upper | Get-Random -Count 1
    $password += $number | Get-Random -Count 1
    $password += $symbol | Get-Random -Count 1

    for ($i = 0; $i -lt ($Length - 4); $i++) {
        $password += $allChars | Get-Random -Count 1
    }

    $passwordArray = $password.ToCharArray()
    $shuffledPassword = $passwordArray | Get-Random -Count $passwordArray.Length
    return -join $shuffledPassword
}
function Get-BuiltInAdmin {
    $admin = Get-LocalUser | Where-Object { $_.SID -like "*-500" }
    if (-not $admin) { throw "BUILT-IN ADMINISTRATOR ACCOUNT NOT FOUND (SID *-500)." }
    return $admin
}
function Load-UserHive {
    param([string]$HivePath,[string]$MountName)
    if (-not (Test-Path $HivePath)) { throw "HIVE NOT FOUND: $HivePath" }
    & reg.exe load ("HKU\{0}" -f $MountName) $HivePath | Out-Null
}
function Unload-UserHive {
    param([string]$MountName)
    $key = "HKU\{0}" -f $MountName
    for ($i = 0; $i -lt 3; $i++) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        & reg.exe unload $key 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Milliseconds 400
    }
}
function Set-AdminAccountPictures {
    param(
        [string]$ImageSourcePng,
        [string]$AdminSid
    )
    try {
        if (-not (Test-Path $ImageSourcePng)) {
            Write-Host "   (skip) Photo source not found: $ImageSourcePng"
            return
        }
        Add-Type -AssemblyName "System.Drawing"
        $prefixGuid = [guid]::NewGuid().ToString("B").ToUpper()
        $destDir    = Join-Path $env:PUBLIC ("AccountPictures\{0}" -f $AdminSid)

        if (Test-Path $destDir) { Remove-Item -Force -Recurse -Path $destDir }
        $null = New-Item -ItemType Directory -Force -Path $destDir

        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$AdminSid"
        if (-not (Test-Path $regPath)) { $null = New-Item -Path $regPath -Force }

        $photo   = [System.Drawing.Image]::FromFile($ImageSourcePng)
        $sizes   = @(32,40,48,64,96,192,208,240,424,448,1080)

        $pngCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/png" }
        $enc      = [System.Drawing.Imaging.Encoder]::Quality
        $params   = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($enc, 90)

        foreach ($sz in $sizes) {
            $bmp = New-Object System.Drawing.Bitmap $sz, $sz
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gfx.Clear([System.Drawing.Color]::FromArgb(20, 21, 25))  # Dark background matching logo
            $gfx.DrawImage($photo, 0, 0, $sz, $sz)
            $destFile = Join-Path $destDir ("{0}-Image{1}.png" -f $prefixGuid,$sz)
            $bmp.Save($destFile, $pngCodec, $params)
            $gfx.Dispose()
            $bmp.Dispose()
            Set-ItemProperty -Path $regPath -Name ("Image{0}" -f $sz) -Value $destFile
        }
        $photo.Dispose()
        Write-Host "   Profile pictures applied under $destDir"
    } catch {
        Write-Host "   (warn) Account picture failed: $($_.Exception.Message)"
    }
}
function Set-AdminWallpaper {
    param(
        [string]$WallpaperPng,
        [string]$AdminSid,
        [string]$AdminProfileNtuserPath
    )
    try {
        if (-not (Test-Path $WallpaperPng)) {
            Write-Host "   (skip) Wallpaper source not found: $WallpaperPng"
            return
        }
        $liveRoot = "Registry::HKEY_USERS\$AdminSid"
        if (Test-Path $liveRoot) {
            $desktopKey = Join-Path $liveRoot "Control Panel\Desktop"
            if (-not (Test-Path $desktopKey)) { $null = New-Item -Path $desktopKey -Force }
            Set-ItemProperty -Path $desktopKey -Name "Wallpaper" -Value $WallpaperPng
            Write-Host "   Wallpaper registry set (logged on): $WallpaperPng"
            return
        }
        if (-not (Test-Path $AdminProfileNtuserPath)) {
            Write-Host "   (warn) NTUSER.DAT not found for wallpaper: $AdminProfileNtuserPath. User profile may not have been created yet (first login required)."
            return
        }
        $mount = "TempHive$($AdminSid.Substring($AdminSid.Length - 8))"
        try {
            Load-UserHive -HivePath $AdminProfileNtuserPath -MountName $mount
            $desktopKey = "Registry::HKEY_USERS\{0}\Control Panel\Desktop" -f $mount
            if (-not (Test-Path $desktopKey)) { $null = New-Item -Path $desktopKey -Force }
            Set-ItemProperty -Path $desktopKey -Name "Wallpaper" -Value $WallpaperPng
            Write-Host "   Wallpaper registry set: $WallpaperPng"
        } finally {
            Unload-UserHive -MountName $mount
        }
    } catch {
        Write-Host "   (warn) Wallpaper set failed: $($_.Exception.Message)"
    }
}
# ============================================================================

try {
    # =============================================================================
    # PRECHECKS
    # =============================================================================
    Write-Section "PRECHECKS"
    $elev = Test-IsElevated
    PrintKV "Elevated"               ($(if ($elev) {"Yes"} else {"No"}))
    if (-not $elev) { throw "SCRIPT MUST RUN ELEVATED." }

    # =============================================================================
    # GATHER SYSTEM / TARGETS
    # =============================================================================
    Write-Section "TARGET ACCOUNTS / PATHS"
    $admin = Get-BuiltInAdmin
    $AdminUser = $admin.Name
    $AdminSID  = $admin.SID.Value
    PrintKV "Built-in Admin"      "$AdminUser ($AdminSID)"

    $AdminProfileObj  = Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $AdminSID }
    $AdminProfilePath = if ($AdminProfileObj) { $AdminProfileObj.LocalPath } else { "C:\Users\Administrator" }
    $NtUserDatPath    = if ($AdminProfilePath) { Join-Path $AdminProfilePath 'NTUSER.DAT' } else { $null }

    PrintKV "Admin Profile Path"     ($(if ($AdminProfilePath) { $AdminProfilePath } else { "<none>" }))
    PrintKV "Admin NTUSER.DAT"       ($(if ($NtUserDatPath)   { $NtUserDatPath   } else { "<none>" }))

    # =============================================================================
    # BUILT-IN ADMINISTRATOR MANAGEMENT
    # =============================================================================
    Write-Section "BUILT-IN ADMINISTRATOR MANAGEMENT"

    # Rename the built-in admin account
    if ($admin.Name -ne $BuiltInAdminNewName) {
        Rename-LocalUser -Name $admin.Name -NewName $BuiltInAdminNewName
        PrintKV "Built-in Admin Renamed" "$($admin.Name) -> $BuiltInAdminNewName"
    } else {
        PrintKV "Built-in Admin Name" "Already '$BuiltInAdminNewName'"
    }

    # Clear FullName to avoid confusion with limehawk account on login screen
    Set-LocalUser -Name $BuiltInAdminNewName -FullName ""
    PrintKV "Built-in Admin FullName" "Cleared"

    # Set a new password for the built-in admin
    $BuiltInAdminPassword = New-RandomPassword -Length $GeneratedPasswordLength
    try {
        Set-LocalUser -Name $BuiltInAdminNewName -Password (ConvertTo-SecureString $BuiltInAdminPassword -AsPlainText -Force)
        PrintKV "Built-in Admin Password" "Set"
    } catch {
        throw "Failed to set password on built-in Administrator account: $($_.Exception.Message)"
    }

    Write-LevelSlot -Name "password_admin" -Value $BuiltInAdminPassword

    # Ensure the built-in admin account is disabled
    try {
        Disable-LocalUser -Name $BuiltInAdminNewName
        PrintKV "Built-in Admin Status" "Disabled"
    } catch {
        throw "Failed to disable built-in Administrator account: $($_.Exception.Message)"
    }

    # =============================================================================
    # MSP ADMINISTRATOR ACCOUNT MANAGEMENT
    # =============================================================================
    Write-Section "MSP ADMINISTRATOR ACCOUNT MANAGEMENT"

    # Check if the MSP admin account exists
    $MspAdmin = Get-LocalUser -Name $MspAdminName -ErrorAction SilentlyContinue
    if (-not $MspAdmin) {
        # Create the MSP admin account
        $MspAdminPassword = New-RandomPassword -Length $GeneratedPasswordLength
        try {
            $MspAdmin = New-LocalUser -Name $MspAdminName -Password (ConvertTo-SecureString $MspAdminPassword -AsPlainText -Force) -FullName $MspAdminFullName -Description "Limehawk MSP Admin Account"
            PrintKV "MSP Admin Account" "Created '$MspAdminName'"
        } catch {
            throw "Failed to create MSP admin account: $($_.Exception.Message)"
        }
        # Add the new user to the local Administrators group
        try {
            Add-LocalGroupMember -Group "Administrators" -Member $MspAdminName
            PrintKV "MSP Admin Group" "Added to Administrators"
        } catch {
            throw "Failed to add MSP admin to Administrators group: $($_.Exception.Message)"
        }
    } else {
        PrintKV "MSP Admin Account" "Already exists"
        # Just set a new password if the account already exists
        $MspAdminPassword = New-RandomPassword -Length $GeneratedPasswordLength
        try {
            Set-LocalUser -Name $MspAdminName -Password (ConvertTo-SecureString $MspAdminPassword -AsPlainText -Force)
            PrintKV "MSP Admin Password" "Set"
        } catch {
            throw "Failed to set password on MSP admin account: $($_.Exception.Message)"
        }
    }

    Write-LevelSlot -Name "password_msp" -Value $MspAdminPassword

    # Ensure the MSP admin account is enabled
    try {
        Enable-LocalUser -Name $MspAdminName
        PrintKV "MSP Admin Status" "Enabled"
    } catch {
        throw "Failed to enable MSP admin account: $($_.Exception.Message)"
    }

    # Ensure MSP admin is visible on login screen (remove from hidden accounts list)
    $hiddenUsersPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
    if (Test-Path $hiddenUsersPath) {
        $hiddenValue = Get-ItemProperty -Path $hiddenUsersPath -Name $MspAdminName -ErrorAction SilentlyContinue
        if ($null -ne $hiddenValue -and $hiddenValue.$MspAdminName -eq 0) {
            Remove-ItemProperty -Path $hiddenUsersPath -Name $MspAdminName -ErrorAction SilentlyContinue
            PrintKV "MSP Admin Visibility" "Unhidden from login screen"
        } else {
            PrintKV "MSP Admin Visibility" "Already visible"
        }
    } else {
        PrintKV "MSP Admin Visibility" "No hidden accounts registry"
    }

    # Get MSP Admin SID and Profile Path (after account is created/verified)
    $MspAdmin = Get-LocalUser -Name $MspAdminName
    $MspAdminSID = $MspAdmin.SID.Value
    $MspAdminProfileObj = Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $MspAdminSID }
    $MspAdminProfilePath = if ($MspAdminProfileObj) { $MspAdminProfileObj.LocalPath } else { "C:\Users\$MspAdminName" }
    $MspAdminNtUserDatPath = if ($MspAdminProfilePath) { Join-Path $MspAdminProfilePath 'NTUSER.DAT' } else { $null }

    PrintKV "MSP Admin SID"              $MspAdminSID
    PrintKV "MSP Admin Profile Path"     ($(if ($MspAdminProfilePath) { $MspAdminProfilePath } else { "<none>" }))
    PrintKV "MSP Admin NTUSER.DAT"       ($(if ($MspAdminNtUserDatPath) { $MspAdminNtUserDatPath } else { "<none>" }))

    # =============================================================================
    # OLD MSP ACCOUNT CLEANUP
    # =============================================================================
    Write-Section "OLD MSP ACCOUNT CLEANUP"
    $OldMspAccounts = @("m5sadmin", "tlitlocal", "clientadmin")
    $BuiltInAdminSID = (Get-LocalUser -Name $BuiltInAdminNewName).SID.Value # Get SID of the built-in admin

    foreach ($accountName in $OldMspAccounts) {
        $user = Get-LocalUser -Name $accountName -ErrorAction SilentlyContinue
        if ($user) {
            if ($user.SID.Value -eq $BuiltInAdminSID) {
                PrintKV "Skipping Built-in Admin" "Account '$accountName' is the built-in Administrator (SID: $BuiltInAdminSID). Not deleting."
            } else {
                try {
                    Remove-LocalUser -Name $accountName -ErrorAction Stop
                    PrintKV "Removed Old Account" $accountName
                } catch {
                    PrintKV "Error Removing Account" "Failed to remove '$accountName': $($_.Exception.Message)"
                }
            }
        } else {
            PrintKV "Old Account Check" "'$accountName' not found"
        }
    }




    # =============================================================================
    # ACCOUNT PICTURE + WALLPAPER
    # =============================================================================
    Write-Section "ADMIN PICTURE & WALLPAPER"

    # Clean up old .png profile photo if it exists
    if (Test-Path $OldPhotoSource) {
        Remove-Item -Path $OldPhotoSource -Force -ErrorAction SilentlyContinue
        PrintKV "Removed Old Photo" $OldPhotoSource
    }

    PrintKV "Photo Source"            ($(if (Test-Path $PhotoSource) {$PhotoSource}else{"<missing>"}))
    PrintKV "Wallpaper Path"          ($(if (Test-Path $WallpaperPath) {$WallpaperPath}else{"<missing>"}))

    # Branding for Built-in Admin (renamed to hawkadmin)
    Write-Host "   [$BuiltInAdminNewName] Applying profile picture..."
    Set-AdminAccountPictures -ImageSourcePng $PhotoSource -AdminSid $AdminSID
    Write-Host "   [$BuiltInAdminNewName] Applying wallpaper..."
    Set-AdminWallpaper        -WallpaperPng  $WallpaperPath -AdminSid $AdminSID -AdminProfileNtuserPath $NtUserDatPath

    # Branding for MSP Admin (limehawk)
    Write-Host "   [$MspAdminName] Applying profile picture..."
    Set-AdminAccountPictures -ImageSourcePng $PhotoSource -AdminSid $MspAdminSID
    Write-Host "   [$MspAdminName] Applying wallpaper..."
    Set-AdminWallpaper        -WallpaperPng  $WallpaperPath -AdminSid $MspAdminSID -AdminProfileNtuserPath $MspAdminNtUserDatPath

    # =============================================================================
    # DONE
    # =============================================================================
    Write-Section "FINAL STATUS"
    PrintKV "hawkadmin (built-in)" "Disabled, password in password_admin slot"
    PrintKV "limehawk (MSP admin)" "Enabled, password in password_msp slot"

    Write-Section "SCRIPT COMPLETED" "OK"
    exit 0
}
catch {
    Write-Host ""
    Write-Host "[ERROR] SCRIPT FAILED"
    Write-Host "=============================================================="
    PrintKV "ERROR MESSAGE" ($_.Exception.Message.ToUpper())
    exit 1
}
