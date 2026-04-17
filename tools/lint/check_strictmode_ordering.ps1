<#
.SYNOPSIS
  Flags .ps1 scripts where Set-StrictMode fires BEFORE SuperOps runtime-variable
  placeholder reads. That ordering crashes with VariableIsUndefined whenever
  a placeholder isn't injected (e.g., the tech leaves the field blank in
  SuperOps).

.DESCRIPTION
  The fix is to put the HARDCODED INPUTS block BEFORE Set-StrictMode so
  `"$MissingPlaceholder"` expands quietly to empty string, then the
  `if ($var -eq '$' + 'Placeholder')` fall-back normalizes it. See
  docs/powershell_script_guidelines.md for the prescribed layout.

.PARAMETER Path
  Directory or file glob to scan. Defaults to scripts/ under the repo root.

.EXAMPLE
  pwsh ./tools/lint/check_strictmode_ordering.ps1
  pwsh ./tools/lint/check_strictmode_ordering.ps1 -Path scripts/prinstall_*.ps1

.OUTPUTS
  Exit code 0 if clean, 1 if any file violates the rule. Prints one line
  per violation: `FILE:LINE - description`.
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot '..' '..' 'scripts' '*.ps1')
)

$ErrorActionPreference = 'Stop'

$placeholderPattern = '^\$\w+\s*=\s*"\$[A-Z]\w+"'
$strictModePattern  = '^Set-StrictMode -Version Latest\s*$'

$violations = @()

$files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue
foreach ($file in $files) {
    $lines = Get-Content -LiteralPath $file.FullName

    $strictIdx = -1
    $firstPlaceholderIdx = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($strictIdx -eq -1 -and $lines[$i] -match $strictModePattern) {
            $strictIdx = $i
        }
        if ($firstPlaceholderIdx -eq -1 -and $lines[$i] -match $placeholderPattern) {
            $firstPlaceholderIdx = $i
        }
    }

    if ($strictIdx -ge 0 -and $firstPlaceholderIdx -ge 0 -and $strictIdx -lt $firstPlaceholderIdx) {
        $rel = Resolve-Path -LiteralPath $file.FullName -Relative
        $violations += [pscustomobject]@{
            File = $rel
            StrictModeLine  = $strictIdx + 1
            FirstInputLine  = $firstPlaceholderIdx + 1
        }
    }
}

if ($violations.Count -eq 0) {
    Write-Host "strictmode-ordering: OK ($($files.Count) file(s) scanned)"
    exit 0
}

Write-Host "strictmode-ordering: $($violations.Count) violation(s)"
Write-Host ""
foreach ($v in $violations) {
    Write-Host ("{0}:{1} - Set-StrictMode fires before first placeholder read at line {2}" -f `
        $v.File, $v.StrictModeLine, $v.FirstInputLine)
}
Write-Host ""
Write-Host "Move Set-StrictMode to AFTER the HARDCODED INPUTS block."
Write-Host "See docs/powershell_script_guidelines.md for the prescribed layout."
exit 1
