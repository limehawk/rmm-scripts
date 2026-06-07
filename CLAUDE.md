# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Production-ready PowerShell, shell, VBScript, and batch scripts for RMM platforms (SuperOps, Datto, NinjaRMM).

## Repository Structure

- `scripts/` - Production scripts (`.ps1`, `.sh`, `.vbs`, `.bat`)
- `docs/` - Documentation and style guidelines
- `wiki/` - GitHub wiki content

## Script Style Requirements

**All scripts must follow the Limehawk Script Framework.**

Read the complete guidelines before creating or modifying scripts:
- PowerShell: `docs/powershell_script_guidelines.md`
- Bash: `docs/bash_script_guidelines.md`
- VBScript: `docs/vbscript_script_guidelines.md`
- Batch: `docs/batch_script_guidelines.md`

Key points:
- Use snake_case filenames (`speedtest_to_superops.ps1`)
- Hardcode all inputs (no `param()` blocks, no `WScript.Arguments`, no `%1`/`%2`)
- Include ASCII art header and README block
- Exit 0 on success, exit 1 on failure

## Script Framework Engine (MANDATORY)

The `script-framework-engine` agent is the single authority for framework compliance. It operates in four modes:

- **validate** — Read-only compliance check. Report violations.
- **fix** — Auto-repair header formatting, regenerate sidecar readme, sync sidecar fields.
- **scaffold** — Generate a new framework-compliant script + YAML sidecar from a description.
- **bump** — Increment version, update DATE, add CHANGELOG stub.

**When to use each mode:**
- After creating or modifying any `.ps1`, `.sh`, `.vbs`, or `.bat` file, run in **validate** mode before committing.
- When the user asks to create a new script, run in **scaffold** mode.
- When modifying an existing script, run in **bump** mode first to increment the version.
- When sidecar YAMLs are stale or the user asks to fix formatting, run in **fix** mode.

### Version Bumping

When modifying ANY existing script, the version **MUST** be updated:
1. **VERSION** - Increment appropriately (major.minor.patch)
   - Major: Breaking changes or significant rewrites
   - Minor: New features or functionality
   - Patch: Bug fixes or minor tweaks
2. **CHANGELOG** - Add entry at top: `YYYY-MM-DD vX.Y.Z Description of changes`
3. **README sections** - Update any affected sections (PURPOSE, BEHAVIOR, REQUIRED INPUTS, etc.)

Use `script-framework-engine` in **bump** mode to automate version increments.

