# File Search via Everything — Design Spec

**Date:** 2026-03-20
**Script:** `file_search_everything.ps1`

## Purpose

A PowerShell script deployed to Windows endpoints via RMM (SuperOps/Datto/NinjaRMM) that searches the entire system for files matching a hardcoded pattern using Voidtools Everything. Results are output to stdout for capture by the RMM platform.

## Approach

Use Everything's built-in CLI capabilities (`Everything.exe -search <pattern>`) for near-instant full-drive file search. This avoids the separate `es.exe` download — Everything.exe itself supports command-line search with stdout output. Install via winget if not already present, perform the search, and uninstall if the script installed it.

## Hardcoded Inputs

| Variable | Default | Description |
|----------|---------|-------------|
| `$searchTerm` | `landtrust` | Search pattern passed to Everything (uses Everything search syntax) |

## Script Flow

### 1. Input Validation
- Validate `$searchTerm` is not null/empty.

### 2. Environment Detection
- Detect SYSTEM vs user context (RMM runs as SYSTEM).
- Resolve winget path accordingly (WindowsApps path resolution for SYSTEM context).
- Check if Everything is already installed by looking for `Everything.exe` in Program Files.
- Check if Everything.exe is already running (track with `$everythingWasRunning`).

### 3. Install Everything (conditional)
- If Everything is not present, install via winget with `--silent --accept-source-agreements --accept-package-agreements`.
- Set `$scriptInstalledEverything = $true` to track cleanup responsibility.

### 4. Start Everything & Wait for Index
- Install and start the Everything service via `Everything.exe -install-service` and `Everything.exe -start-service` (works in SYSTEM context without a desktop session).
- Poll readiness by running a known-good search (e.g., `Everything.exe -search notepad.exe`) until results appear.
- Poll every 2 seconds, timeout after 60 seconds total.

### 5. Search & Output
- Run `Everything.exe -search $searchTerm` — results go directly to stdout, one path per line.
- Count results and print summary.
- If no matches: "No files found matching: $searchTerm"

### 6. Cleanup
- If `$scriptInstalledEverything` is true:
  - Stop and remove the Everything service: `Everything.exe -uninstall-service`
  - Uninstall via winget with `--silent --force`.
  - Remove leftover directories: `C:\Program Files\Everything\`, `$env:ProgramData\Everything\`.
- If Everything was pre-existing but not running: stop the service we started.
- If Everything was pre-existing and already running: leave it alone.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Winget not available | Error message with guidance, exit 1 |
| Everything already installed | Skip install, skip uninstall, still run search |
| Everything already running | Skip start, skip stop — don't disrupt user |
| No results | Clean message: "No files found matching: ..." |
| Index build timeout (60s) | Error message, attempt cleanup, exit 1 |
| Multi-drive system | Everything indexes all NTFS volumes by default — results may include D:\, E:\, etc. |

## Console Sections

```
[INFO] INPUT VALIDATION
[INFO] ENVIRONMENT DETECTION
[RUN]  INSTALL EVERYTHING        (conditional)
[RUN]  BUILD INDEX
[RUN]  FILE SEARCH
[INFO] SEARCH RESULTS
[RUN]  CLEANUP                   (conditional)
[OK]   FINAL STATUS
[OK]   SCRIPT COMPLETED
```

## Prerequisites

- Windows 10 1709+ or Windows 11 (winget availability)
- Administrator privileges (needed for winget install/uninstall and Everything service)
- No external modules required

## Exit Codes

- 0 = Success (results found or no results — search completed)
- 1 = Failure (winget missing, install failed, index timeout)

## Key Technical Details

- **No es.exe dependency** — `Everything.exe` supports `-search` with stdout output directly, eliminating the need for a separate es.exe download.
- **Service mode for SYSTEM context** — `Everything.exe -install-service` / `-start-service` runs headless without a desktop session, which is how RMM scripts execute.
- **SYSTEM context winget** — `Get-Command winget` fails under SYSTEM; must resolve full path via `Resolve-Path` in WindowsApps.
- **Index build time** — typically 1-3 seconds for a standard Windows install (~100k-200k files). 60-second timeout is generous.
- **Everything search syntax** — not standard glob. Wildcards are implicit (searching `landtrust` matches any path containing that string). See Everything docs for advanced syntax.
