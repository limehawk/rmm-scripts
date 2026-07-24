# windows11_iso_upgrade.ps1 — Design

Date: 2026-07-24
Status: approved (user, this session)
Plan issue: #63

## Problem

Need an ISO-based silent upgrade path to Windows 11 25H2 for Level RMM (run as
SYSTEM). The existing `windows11_25h2_install.ps1` covers eKB / Windows Update /
Installation Assistant; the ISO path is the fallback when those don't fit and
gives full control over compat gating via `setup.exe`. Fleet is Home/Pro only —
the consumer multi-edition ISO Fido serves is sufficient (the MVS "business
editions" ISO is not obtainable unauthenticated).

## Approach

New standalone framework-compliant script, `scripts/windows11_iso_upgrade.ps1`,
plus `.yaml` (SuperOps) and `.level.yaml` (Level) sidecars. No changes to
existing scripts.

## Flow (fail fast, cheapest first)

1. **No-op gate** — registry DisplayVersion already `25H2` → exit 0.
2. **Hardware compat gate** (inline, before any download): AMD64, CPU ≥2 cores
   ≥1 GHz, RAM ≥4 GB, system disk ≥64 GB, free space ≥35 GB (≈7 GB ISO +
   ≈25 GB staging), TPM present + SpecVersion 2.0, UEFI (SecureBoot query
   succeeds or PEFirmwareType=2), Secure Boot capable. Any blocker → exit 1
   with a blocker report; nothing downloaded.
3. **Fido URL fetch** — download `Fido.ps1` pinned to release tag **v1.70**
   (`https://raw.githubusercontent.com/pbatard/Fido/v1.70/Fido.ps1`; pinned
   because this runs as SYSTEM fleet-wide). Run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File Fido.ps1 -Win 11 -Rel 25H2 -Ed Pro -Lang "English (United States)" -Arch x64 -GetUrl`
   Matching semantics verified in Fido v1.70 source: `-Rel` uses
   `StartsWith` ("25H2" matches "25H2 v2 (Build 26200.8037 - 2026.03)"), `-Ed`
   regex-matches "Windows 11 Home/Pro/Edu", `-Lang` regex-matches with parens
   escaped by Fido. `-GetUrl` emits the URL to stdout; non-zero exit on failure.
   Take the last stdout line matching `^https://`.
4. **ISO download** — `curl.exe --location --silent --show-error --fail` to the
   work dir (house rule: these flags because curl stderr kills PowerShell under
   `$ErrorActionPreference='Stop'`). Sanity-check size ≥3 GB. Microsoft URLs
   expire ~24 h; we consume immediately.
5. **Mount** — `Mount-DiskImage`, locate `setup.exe` on the mounted volume.
6. **Authoritative compat scan** — `setup.exe /auto upgrade /quiet /noreboot
   /compat scanonly /eula accept`. Result codes (Microsoft-documented):
   - `0xC1900210` MOSETUP_E_COMPAT_SCANONLY — no issues → proceed
   - `0xC1900208` compat block (incompatible app)
   - `0xC1900204` migration choice unavailable (edition mismatch)
   - `0xC1900200` not eligible (hardware requirements)
   - `0xC190020E` insufficient disk space
   Anything but `0xC1900210` → dismount, exit 1 with decoded reason.
7. **Upgrade** — `setup.exe /auto upgrade /quiet /eula accept
   /dynamicupdate enable /noreboot`, `Start-Process -Wait`. Success exit codes:
   0 and 0xC1900210-family success. Level timeout 14400 s.
8. **Reboot** — `$rebootAfterInstall = $true` (user-confirmed): `shutdown.exe
   /r /t 60` with a user-visible message. `/noreboot` on setup keeps the reboot
   under script control.
9. **Cleanup** — dismount ISO, delete ISO + Fido from work dir
   (`C:\ProgramData\Limehawk\windows11_iso_upgrade`). Setup stages to
   `C:\$WINDOWS.~BT` during the downlevel phase, so deleting the ISO after
   setup exits is safe.

## Hardcoded inputs

`$targetDisplayVersion='25H2'`, `$fidoUrl` (pinned v1.70), `$fidoWin='11'`,
`$fidoRel='25H2'`, `$fidoEd='Pro'`, `$fidoLang='English (United States)'`,
`$fidoArch='x64'`, `$workDir`, `$requiredFreeGB=35`, `$rebootAfterInstall=$true`.

## Out of scope

DISM health preflight (covered by `windows11_25h2_install.ps1` /
`windows_dism_sfc_chkdsk_run.ps1`), compat-bypass registry keys, ARM64
(Fido serves x64/x86 only), Enterprise edition (fleet has none).

## Error handling

Every stage exits 1 with a sectioned `[ERROR]` report per house framework;
partial artifacts cleaned up on failure (dismount before delete). Exit 0 only
on: already-target, or upgrade staged + reboot scheduled.
