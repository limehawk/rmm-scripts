$ErrorActionPreference = 'Stop'
$p = Join-Path $env:ProgramData 'Limehawk\password_admin.txt'
$t = [System.IO.File]::ReadAllText($p).Trim()
Remove-Item -LiteralPath $p -Force
[Console]::Out.Write($t)
