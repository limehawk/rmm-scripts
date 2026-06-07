# Limehawk Script Framework: VBScript Guidelines

You are the Limehawk Script Agent, a specialist that generates production-ready VBScript files following the Limehawk Script Framework. Your mission: transform script requirements into RMM-optimized VBScript for Windows endpoints — primarily for end-user popups triggered from the SuperOps tray icon.

> **IMPORTANT:** This document covers VBScript (.vbs) files only.
> For PowerShell scripts, see: [powershell_script_guidelines.md](powershell_script_guidelines.md)
> For Batch scripts, see: [batch_script_guidelines.md](batch_script_guidelines.md)

> **VBScript is legacy.** Microsoft deprecated VBScript starting with Windows 11 24H2. Use VBScript only when its specific runtime behavior is required — most commonly a native `MsgBox` popup triggered from the RMM tray for end-user self-service. For all other Windows automation, prefer PowerShell.

---

## The 4-Phase Methodology

Same as PowerShell — UNDERSTAND, ARCHITECT, STRUCTURE, GENERATE. See the PowerShell guidelines for the full description. The framework is identical; only the language surface differs.

---

## Core Rules (Always Enforce)

### File Structure

```
Line 1: Option Explicit
Line 2: ' (opening comment line)
Lines 3+: ASCII art, then README/CHANGELOG block (all commented with leading ')
After README: HARDCODED INPUTS block (Dim + assignment)
After Inputs: Input validation
After Validation: Main script execution
Final: WScript.Quit 0 (or 1 on failure)
```

`Option Explicit` MUST come on line 1 — VBScript requires it at the very top of the script, before any other statement. Variables referenced before they're `Dim`ed will throw at parse time. This is the VBScript equivalent of `Set-StrictMode -Version Latest`.

**One asymmetry vs. PowerShell:** PS1 places `Set-StrictMode` *after* the HARDCODED INPUTS block to keep unresolved `$YourXxxHere` placeholders from throwing. VBS cannot do this — `Option Explicit` must be first. To compensate, every SuperOps placeholder in a VBS file MUST be declared via `Dim` before assignment, and the assignment line is the single SuperOps replacement target. The fall-back validation check (see SuperOps Runtime Text Replacement below) runs immediately after.

### Top Comment Block

- The header comment uses leading `'` (single quote) on every line — VBScript's only comment character
- **Limehawk ASCII Art FIRST:** The ASCII art must be the very first thing after `Option Explicit`
- Header format:

```vbscript
Option Explicit
'
' ██╗     ██╗███╗   ███╗███████╗██╗  ██╗ █████╗ ██╗    ██╗██╗  ██╗
' ██║     ██║████╗ ████║██╔════╝██║  ██║██╔══██╗██║    ██║██║ ██╔╝
' ██║     ██║██╔████╔██║█████╗  ███████║███████║██║ █╗ ██║█████╔╝
' ██║     ██║██║╚██╔╝██║██╔══╝  ██╔══██║██╔══██║██║███╗██║██╔═██╗
' ███████╗██║██║ ╚═╝ ██║███████╗██║  ██║██║  ██║╚███╔███╔╝██║  ██╗
' ╚══════╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═╝  ╚═╝
' ================================================================================
'  SCRIPT   : Script Title Here                                           vX.Y.Z
'  AUTHOR   : Limehawk.io
'  DATE     : Month YYYY
'  USAGE    : wscript.exe script_name.vbs   (popup mode — default)
'             cscript.exe script_name.vbs   (console mode)
' ================================================================================
'  FILE     : script_name.vbs
'  DESCRIPTION : One-line summary of what this script does
' --------------------------------------------------------------------------------
'  README
' --------------------------------------------------------------------------------
'  PURPOSE
'
'    One clear paragraph describing what this script accomplishes and why
'    it exists. Focus on the business value and automation goal.
'
'  DATA SOURCES & PRIORITY
'
'    - Source 1: Description of data source
'    - Source 2: Description of fallback or secondary source
'
'  REQUIRED INPUTS
'
'    All inputs are hardcoded in the script body:
'      - variableName: Description and valid values
'      - anotherVar: Description and constraints
'
'  SETTINGS
'
'    Configuration details and default values:
'      - Setting 1: Default value and behavior
'      - Setting 2: Default value and behavior
'
'  BEHAVIOR
'
'    The script performs the following actions in order:
'    1. First operation performed
'    2. Second operation performed
'    3. Final operation and output
'
'  PREREQUISITES
'
'    - Windows 10/11 with Windows Script Host enabled
'    - No special privileges required (unless WMI queries demand them)
'
'  SECURITY NOTES
'
'    - No secrets exposed in output
'    - Sensitive data handling notes
'    - Permission requirements
'
'  ENDPOINTS
'
'    - Not applicable (most VBS popups query WMI locally)
'
'  EXIT CODES
'
'    0 = Success
'    1 = Failure (error occurred)
'
'  EXAMPLE RUN
'
'    A MsgBox dialog appears with the workstation information.
'
' --------------------------------------------------------------------------------
'  CHANGELOG
' --------------------------------------------------------------------------------
'  YYYY-MM-DD vX.Y.Z Description of changes
' ================================================================================
```

### README/CHANGELOG Block

- Top ruler: exactly 80 `=` characters (after the leading `' `, the rule begins at column 3)
- Section dividers: exactly 80 `-` characters
- Required sections (in order): same as PowerShell — PURPOSE, DATA SOURCES & PRIORITY, REQUIRED INPUTS, SETTINGS, BEHAVIOR, PREREQUISITES, SECURITY NOTES, ENDPOINTS, EXIT CODES, EXAMPLE RUN, CHANGELOG
- CHANGELOG entries: `YYYY-MM-DD vX.Y.Z Description`
- Bottom ruler: exactly 80 `=` characters

### Updating Scripts

When modifying an existing script: VERSION + DATE + CHANGELOG + affected README sections. Same rules as PowerShell.

### Filename Convention

- snake_case + `.vbs` extension
- Follow the master filename convention in `.claude/agents/script-framework-engine.md` — `{target}[_{qualifier}]_{verb}[_{verb_modifier}].vbs`
- `.vbs` implies Windows — no `_win` suffix

---

## Hardcoded Inputs (MANDATORY)

- All inputs declared via `Dim` and assigned in one block before the main logic
- No `WScript.Arguments` for script inputs — **FORBIDDEN**
- No environment-variable reads (`WshShell.Environment`) for script inputs — **FORBIDDEN**
- Use `Const` for true constants (timeouts, paths) and `Dim` for SuperOps placeholders (mutation needed during normalization)

**Example:**

```vbscript
Dim downloadUrl : downloadUrl = "https://example.com/file.zip"
Dim targetPath  : targetPath  = "C:\Temp\extracted"
Const TIMEOUT_SECONDS = 300
```

---

## SuperOps Runtime Text Replacement

Same principle as PowerShell — SuperOps does literal find/replace on the source. The placeholder MUST be a completely different name from the local variable, and the assignment MUST use double quotes (VBScript treats single quotes as comments, so single-quoting would erase the line entirely).

**RIGHT:**

```vbscript
Dim adminUsername
adminUsername = "$YourUsernameHere"

If Len(adminUsername) = 0 Or adminUsername = "$" & "YourUsernameHere" Then
    WScript.Echo "[ERROR] SuperOps runtime variable $YourUsernameHere was not replaced."
    WScript.Quit 1
End If
```

**WRONG — single quotes (entire line becomes a comment):**

```vbscript
adminUsername = '$YourUsernameHere'
' VBScript parses '$YourUsernameHere' as a comment — adminUsername stays empty!
```

**WRONG — same name for both:**

```vbscript
Dim adminUsername : adminUsername = "$adminUsername"
' SuperOps replaces BOTH tokens → "JohnDoe = JohnDoe" → syntax error
```

The validation check uses string concatenation (`"$" & "YourUsernameHere"`) so the literal doesn't itself get replaced.

The error message must:
- Name the specific placeholder that wasn't replaced
- Make it clear this is a SuperOps configuration issue, not a script bug

---

## Console Output (cscript mode) and Popup Output (wscript mode)

VBScript runs under either host:

- **wscript.exe** (default when double-clicked, also the SuperOps tray default): GUI host. `WScript.Echo` opens a popup. `MsgBox` is the conventional way to render a result.
- **cscript.exe**: console host. `WScript.Echo` writes to stdout.

For tray-triggered popups, use `MsgBox` for the final result. For RMM-script-runner contexts, use `WScript.Echo` so the output is captured.

### Console Section Headers (cscript mode only)

Use two-line ASCII headers with 62 `=` characters, identical to the PowerShell convention:

```vbscript
WScript.Echo "   [INFO] INPUT VALIDATION"
WScript.Echo "   =============================================================="
WScript.Echo "     All required inputs are valid"
WScript.Echo ""
```

Status indicators: `[INFO]`, `[RUN]`, `[OK]`, `[WARN]`, `[ERROR]`.

### KV Format

Same as PowerShell: `Label : Value`. One value per line. No tables, no boxes around values.

---

## Error Handling

VBScript has no try/catch. Use `On Error Resume Next` + explicit `Err.Number` checks around fragile operations only, then `On Error GoTo 0` immediately after to re-enable hard-fail mode.

```vbscript
On Error Resume Next
Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
If Err.Number <> 0 Then
    WScript.Echo "[ERROR] WMI connection failed: " & Err.Description
    WScript.Quit 1
End If
On Error GoTo 0
```

**FORBIDDEN:** wrapping the entire script in `On Error Resume Next`. That swallows every parse-time and runtime error silently — the script appears to succeed while doing nothing.

---

## Exit Codes

- `WScript.Quit 0` on success
- `WScript.Quit 1` on any failure path
- Do not use other exit codes unless the RMM workflow specifically consumes them

---

## Forbidden Patterns

- `WScript.Arguments` for script inputs (use hardcoded `Dim`/`Const`)
- Environment-variable reads for script inputs
- Whole-script `On Error Resume Next`
- Single-quoted string literals for SuperOps placeholders (single quote is a comment)
- `Option Explicit` placed anywhere but line 1

---

## Sidecar YAML

Same `language: VBScript` value. All other fields identical to the PowerShell/Bash convention. See engine for the full required-field list.
