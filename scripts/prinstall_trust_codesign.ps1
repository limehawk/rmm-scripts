$ErrorActionPreference = 'Stop'
<#
██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
================================================================================
SCRIPT  : Prinstall Trust Codesign v0.4.10
AUTHOR  : Limehawk.io
DATE      : April 2026
USAGE   : .\prinstall_trust_codesign.ps1
FILE    : prinstall_trust_codesign.ps1
DESCRIPTION : Imports the Prinstall self-signed code signing cert into the
              LocalMachine trust stores so signed prinstall.exe binaries
              pass Smart App Control on managed endpoints.
================================================================================
README
--------------------------------------------------------------------------------
 PURPOSE
   Pushes the Prinstall code signing public cert (prinstall-codesign.cer,
   bundled alongside this script in rmm-scripts/scripts/) into the machine
   trust store on managed endpoints. After this runs, signed prinstall.exe
   release binaries (v0.4.10+) pass Smart App Control without needing a
   publicly-trusted commercial code signing cert.

   Imports to BOTH stores:
   - Cert:\LocalMachine\Root          — satisfies Authenticode chain validation
   - Cert:\LocalMachine\TrustedPublisher — satisfies Smart App Control policy

   Idempotent — checks the thumbprint before importing. Safe to re-run as
   part of routine agent provisioning or after fleet drift checks.

 DATA SOURCES & PRIORITY
   1) prinstall-codesign.cer co-located with this script (default)
   2) Explicit path via $certPathInput (SuperOps: $CertPath) — override
      for test cases or alternate cert sources

 REQUIRED INPUTS
   - $certPathInput : (optional) Full path to .cer file. Empty/unset uses
                       the default next to this script.
                       SuperOps runtime variable: $CertPath

 SETTINGS
   - Trust install scope: LocalMachine (requires elevated/SYSTEM context)
   - Matches prinstall: 0.4.10+ (tags signed via .github/workflows/release.yml)
   - Cert validity: 10 years from issuance

 BEHAVIOR
   1. Resolves cert path (explicit input, else co-located default)
   2. Loads cert, extracts thumbprint + subject + expiration
   3. For each of Root and TrustedPublisher:
      a. Checks if cert with matching thumbprint already present
      b. If missing, imports via Import-Certificate
      c. If present, logs "already trusted" and skips
   4. Prints final trust status summary

 PREREQUISITES
   - Windows OS
   - Administrator / SYSTEM privileges (LocalMachine stores require elevation)
   - prinstall-codesign.cer accessible at $certPathInput or co-located

 SECURITY NOTES
   - .cer is a PUBLIC certificate — safe to bundle in the repo
   - Importing to Root grants the cert authority to sign anything — scope is
     limited to the prinstall code signing subject. Trusted Publisher scope
     applies only to Authenticode-signed binaries.
   - No private key is ever distributed. The .pfx lives only in GitHub Actions
     secrets and 1Password.
   - Script touches LocalMachine\Root — this is a meaningful trust delegation.
     Review prinstall-codesign.cer's subject before deploying fleet-wide.

 ENDPOINTS
   - None (local operation only)

 EXIT CODES
   - 0 = Success - cert present in both Root and TrustedPublisher
   - 1 = Failure - cert file missing, import failed, or trust not applied

 EXAMPLE RUN

   [INFO] INPUT VALIDATION
   ==============================================================
   Cert Path       : C:\ProgramData\SuperOps\scripts\prinstall-codesign.cer
   Inputs validated successfully

   [RUN] LOAD CERT
   ==============================================================
   Thumbprint      : A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E7F8A9B0
   Subject         : CN=Prinstall Code Signing, O=Limehawk, C=US
   Issuer          : CN=Prinstall Code Signing, O=Limehawk, C=US
   Not Before      : 2026-04-14
   Not After       : 2036-04-12
   Signature Algo  : sha256RSA

   [RUN] TRUST: LocalMachine\Root
   ==============================================================
   Imported cert into Cert:\LocalMachine\Root

   [RUN] TRUST: LocalMachine\TrustedPublisher
   ==============================================================
   Imported cert into Cert:\LocalMachine\TrustedPublisher

   [OK] FINAL STATUS
   ==============================================================
   Status          : Success
   Root            : Trusted
   TrustedPublisher: Trusted
   Thumbprint      : A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E7F8A9B0

   [OK] SCRIPT COMPLETED
   ==============================================================

CHANGELOG
--------------------------------------------------------------------------------
2026-04-14 v0.4.10 Initial release — imports prinstall-codesign.cer into
                   LocalMachine\Root + LocalMachine\TrustedPublisher so signed
                   prinstall.exe releases pass Smart App Control on managed
                   endpoints. Companion to docs/selfsign-setup.md in the
                   prinstall repo. Version tracks prinstall app version.
================================================================================
#>
# ============================================================================
# HARDCODED INPUTS
# ============================================================================
$certPathInput = "$CertPath"   # optional; empty = use default

# ============================================================================
# INPUT VALIDATION
# ============================================================================

Set-StrictMode -Version Latest

Write-Host ""
Write-Host "[INFO] INPUT VALIDATION"
Write-Host "=============================================================="

$errorOccurred = $false
$errorText = ""

# Resolve cert path: explicit input wins, else default to co-located file.
# Handle the '$CertPath' literal case when SuperOps didn't substitute the
# runtime variable — treat it as "use default" rather than failing.
if ([string]::IsNullOrWhiteSpace($certPathInput) -or $certPathInput -eq '$' + 'CertPath') {
    $defaultPath = Join-Path $PSScriptRoot 'prinstall-codesign.cer'
    $certPath = $defaultPath
} else {
    $certPath = $certPathInput
}

if (-not (Test-Path $certPath)) {
    $errorOccurred = $true
    if ($errorText.Length -gt 0) { $errorText += "`n" }
    $errorText += "- Cert file not found: $certPath"
    $errorText += "`n  Make sure prinstall-codesign.cer is bundled with this script,"
    $errorText += "`n  or pass an explicit path via the CertPath runtime variable."
}

if ($errorOccurred) {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host $errorText
    exit 1
}

Write-Host "Cert Path       : $certPath"
Write-Host "Inputs validated successfully"

# ============================================================================
# LOAD CERT
# ============================================================================
Write-Host ""
Write-Host "[RUN] LOAD CERT"
Write-Host "=============================================================="

try {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certPath
    $thumbprint = $cert.Thumbprint
    $subject = $cert.Subject
    $issuer = $cert.Issuer
    $notBefore = $cert.NotBefore.ToString('yyyy-MM-dd')
    $notAfter = $cert.NotAfter.ToString('yyyy-MM-dd')
    $sigAlgo = $cert.SignatureAlgorithm.FriendlyName

    Write-Host "Thumbprint      : $thumbprint"
    Write-Host "Subject         : $subject"
    Write-Host "Issuer          : $issuer"
    Write-Host "Not Before      : $notBefore"
    Write-Host "Not After       : $notAfter"
    Write-Host "Signature Algo  : $sigAlgo"

    # Soft-warn on expired certs. Still import (the pipeline may be testing a
    # known-expired cert), but surface it prominently so it's obvious in logs.
    if ($cert.NotAfter -lt (Get-Date)) {
        Write-Host ""
        Write-Host "Warning: cert is EXPIRED (NotAfter=$notAfter). Signatures on"
        Write-Host "         binaries signed with this cert will fail chain validation."
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] ERROR OCCURRED"
    Write-Host "=============================================================="
    Write-Host "Failed to load cert from $certPath"
    Write-Host "Error : $($_.Exception.Message)"
    exit 1
}

# ============================================================================
# HELPER — idempotent import
# ============================================================================
function Import-IfMissing {
    param(
        [Parameter(Mandatory)][string]$StorePath,
        [Parameter(Mandatory)][string]$StoreLabel,
        [Parameter(Mandatory)][string]$Thumbprint,
        [Parameter(Mandatory)][string]$CertPath
    )

    Write-Host ""
    Write-Host "[RUN] TRUST: $StoreLabel"
    Write-Host "=============================================================="

    try {
        $existing = Get-ChildItem -Path $StorePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -ieq $Thumbprint }

        if ($existing) {
            Write-Host "Already trusted in $StoreLabel (thumbprint match, no-op)"
            return $true
        }

        Import-Certificate -FilePath $CertPath -CertStoreLocation $StorePath | Out-Null
        Write-Host "Imported cert into $StoreLabel"

        # Verify the import landed — Import-Certificate returns success even
        # when the cert silently drops on some policy-restricted endpoints.
        $verified = Get-ChildItem -Path $StorePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -ieq $Thumbprint }
        if (-not $verified) {
            throw "Import returned success but cert is not present in $StoreLabel"
        }

        return $true
    } catch {
        Write-Host ""
        Write-Host "[ERROR] ERROR OCCURRED"
        Write-Host "=============================================================="
        Write-Host "Failed to import cert into $StoreLabel"
        Write-Host "Error : $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# TRUST: LocalMachine\Root
# ============================================================================
$rootOk = Import-IfMissing `
    -StorePath   'Cert:\LocalMachine\Root' `
    -StoreLabel  'LocalMachine\Root' `
    -Thumbprint  $thumbprint `
    -CertPath    $certPath

# ============================================================================
# TRUST: LocalMachine\TrustedPublisher
# ============================================================================
$pubOk = Import-IfMissing `
    -StorePath   'Cert:\LocalMachine\TrustedPublisher' `
    -StoreLabel  'LocalMachine\TrustedPublisher' `
    -Thumbprint  $thumbprint `
    -CertPath    $certPath

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "[OK] FINAL STATUS"
Write-Host "=============================================================="

if (-not $rootOk -or -not $pubOk) {
    Write-Host "Status          : Failure"
    Write-Host "Root            : $(if ($rootOk) { 'Trusted' } else { 'FAILED' })"
    Write-Host "TrustedPublisher: $(if ($pubOk) { 'Trusted' } else { 'FAILED' })"
    Write-Host "Thumbprint      : $thumbprint"
    exit 1
}

Write-Host "Status          : Success"
Write-Host "Root            : Trusted"
Write-Host "TrustedPublisher: Trusted"
Write-Host "Thumbprint      : $thumbprint"
Write-Host ""
Write-Host "[OK] SCRIPT COMPLETED"
Write-Host "=============================================================="

exit 0
