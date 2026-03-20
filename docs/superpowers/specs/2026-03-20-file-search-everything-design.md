# File Search via Everything — Design Spec

**Date:** 2026-03-20
**Script:** `file_search_everything.ps1`

## Purpose

A PowerShell script deployed to Windows endpoints via RMM (SuperOps/Datto/NinjaRMM) that searches the entire C:\ drive for files matching a hardcoded pattern using Voidtools Everything. Results are output to stdout for capture by the RMM platform.

## Approach

Use Everything's `es.exe` command-line interface for near-instant full-drive file search. Install Everything via winget if not already present, perform the search, and uninstall if the script installed it (leave it alone if it was pre-existing).

## Hardcoded Inputs

| Variable | Default | Description |
|----------|---------|-------------|
| `$searchTerm` | `*landtrust*` | Wildcard pattern passed to es.exe |

## Script Flow

### 1. Input Validation
- Validate `$searchTerm` is not null/empty.

### 2. Environment Detection
- Detect SYSTEM vs user context (RMM runs as SYSTEM).
- Resolve winget path accordingly (WindowsApps path resolution for SYSTEM context).
- Check if Everything is already installed by looking for `Everything.exe` in Program Files.

### 3. Install Everything (conditional)
- If Everything is not present, install via winget: `winget install voidtools.Everything --silent --accept-source-agreements --accept-package-agreements`
- Set `$scriptInstalledEverything = $true` to track cleanup responsibility.

### 4. Start Everything & Wait for Index
- Start `Everything.exe` (needed for es.exe IPC communication).
- Poll `es.exe` with a simple query until it returns results (index is ready).
- Timeout after 60 seconds — if index doesn't build, report error and exit 1.

### 5. Search
- Run `es.exe $searchTerm` and capture output.
- Each result is a full file path, one per line.

### 6. Output Results
- Print each matching file path to stdout.
- Print summary: total count of matches.
- If no matches: "No files found matching: $searchTerm"

### 7. Cleanup
- Stop Everything.exe process.
- If `$scriptInstalledEverything` is true: uninstall via winget and remove leftover files/dirs.
- If Everything was pre-existing: leave it installed, just stop the process we started.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Winget not available | Error message with guidance, exit 1 |
| Everything already installed | Skip install, skip uninstall, still run search |
| No results | Clean message: "No files found matching: ..." |
| Index build timeout (60s) | Error message, attempt cleanup, exit 1 |
| es.exe not found after install | Error message, attempt cleanup, exit 1 |

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
- 1 = Failure (winget missing, install failed, index timeout, es.exe not found)

## Key Technical Details

- **es.exe requires Everything.exe running** — it communicates via IPC, not through the Windows service directly.
- **SYSTEM context winget** — `Get-Command winget` fails under SYSTEM; must resolve full path via `Resolve-Path` in WindowsApps.
- **Index build time** — typically 1-3 seconds for a standard Windows install (~100k-200k files). 60-second timeout is generous.
- **Everything.exe path** — default install location is `C:\Program Files\Everything\Everything.exe`, with `es.exe` in the same directory.
