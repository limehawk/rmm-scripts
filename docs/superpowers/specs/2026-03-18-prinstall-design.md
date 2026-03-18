# Prinstall — Windows Printer Installer TUI

**Date:** 2026-03-18
**Status:** Final
**Project location:** `~/dev/prinstall/`

## Overview

A Rust-based tool for Windows that discovers network printers, finds matching drivers, and installs them. Designed for MSP technicians running it either locally or through RMM remote shells (SuperOps).

Two interface modes, auto-detected:
- **TUI mode** — ratatui interactive interface when a real terminal (PTY) is detected
- **CLI mode** — short subcommands with verbose plain-text output for RMM terminals and scripting

## Use Case

On-site or remote technician needs to install a printer on a Windows machine. They don't know what driver to use. The tool discovers the printer, identifies it, finds the right driver (or offers the universal fallback), and installs everything in one shot.

## Architecture

Four layers:

### 1. Interface Layer

Auto-detects terminal capability via `std::io::stdout().is_terminal()` (stable since Rust 1.70).

**TUI mode** (real terminal): ratatui + crossterm. Interactive lists, search, progress bars, scrollable driver results.

**CLI mode** (pipe/RMM): clap subcommands with rich built-in help. Verbose, readable output by default. `--json` flag for machine-parseable output.

#### CLI Subcommands

```
prinstall                              # TUI if terminal, help if pipe
prinstall scan                         # scan local subnet
prinstall scan 192.168.1.0/24         # scan specific subnet
prinstall id 192.168.1.100            # identify printer at IP
prinstall drivers 192.168.1.100       # show matched + universal drivers
prinstall install 192.168.1.100       # auto-pick best driver, full install
prinstall install 192.168.1.100 --driver "HP Universal Print Driver PCL6"
prinstall install 192.168.1.100 --name "Front Desk Printer"
prinstall install 192.168.1.100 --model "HP LaserJet Pro MFP M428fdw"  # bypass SNMP
```

Global flags:
- `--json` — machine-parseable JSON output
- `--community <string>` — SNMP community string (default: `public`)
- `--model <string>` — manually specify printer model, bypass SNMP discovery
- `-v` / `--verbose` — step-by-step diagnostic output (SNMP queries, driver selection reasoning, PowerShell commands executed)

Each subcommand has thorough `--help` with description, usage examples, and notes about what happens under the hood.

### 2. Core Engine (Rust)

Three modules:

**Discovery** — SNMP queries over UDP port 161 using the `snmp` crate. Hits OID `1.3.6.1.2.1.25.3.2.1.3` (hrDeviceDescr) and `1.3.6.1.2.1.1.1` (sysDescr) for model identification. Default community string `public`, configurable via `--community` flag.

Subnet scan: parallel UDP queries, max 64 concurrent probes, 2-second per-host timeout. Restricted to /24 or smaller for v1 — larger subnets print a warning and require `--force`.

When SNMP returns no results, print diagnostic guidance: common causes (SNMP disabled, non-default community string, firewall blocking UDP 161) and workarounds (try `--community`, use manual `--model` to bypass discovery).

Data collected per printer:
- IP address
- Model string
- Serial number (if available)
- Status (ready/error/offline)

**Driver Matcher** — takes model string, produces ranked driver list in two sections:

*Matched Drivers:*
- Tier 1: Exact match from curated `known_matches.toml` table
- Tier 2: Fuzzy match against locally staged driver names (`pnputil /enum-drivers`) and curated driver names from `drivers.toml` (normalized — strip "MFP", "Series", etc.)

*Universal Drivers (always shown if available for manufacturer):*
- HP → HP Universal Print Driver PCL6
- Ricoh → RICOH Universal PCL6
- Brother → Brother Universal Printer
- Canon → Canon Generic Plus UFR II
- Lexmark → Lexmark Universal v2
- Xerox → Xerox Global Print Driver
- Epson → Epson Universal Print Driver
- Kyocera → Kyocera Classic Universal Driver

Output example:
```
── Matched Drivers ──────────────────────────────────────────
  #1  HP LaserJet Pro MFP M428f PCL-6 (V4)     ★ exact    [Local Store]
  #2  HP LaserJet Pro MFP M428f PCL-6           ● fuzzy    [Local Store]
  #3  HP LaserJet Pro M400 Series PCL-6         ○ fuzzy    [Manufacturer]

── Universal Drivers ────────────────────────────────────────
  #4  HP Universal Print Driver PCL6                       [Manufacturer]
  #5  HP Universal Print Driver PS                         [Manufacturer]
```

Drivers are ranked by confidence within each section. Both sections always visible — no hidden fallback chain.

**Downloader** — fetches driver packages from Windows Update or manufacturer URLs. Downloads to `%TEMP%\prinstall\`, extracts, finds `.inf`, stages via `pnputil`.

**Local learning:** Every successful install logs model string → driver to `C:\ProgramData\prinstall\history.toml`. Uses `C:\ProgramData` since the tool requires admin and may run as SYSTEM (RMM context) — this path is consistent across both interactive and SYSTEM contexts. Schema: `[[installs]]` array with `model`, `driver_name`, `source`, `date` fields. Builds a machine-local match database over time.

### 3. Driver Sources (fallback order for sourcing, not for display)

1. **Local driver store** — `pnputil /enum-drivers`. Already staged = skip download.
2. **Manufacturer download** — `drivers.toml` manifest maps manufacturer → known package URLs. V1 supports ZIP-packaged drivers and CAB files only. EXE/MSI packages are out of scope — the tool prints the download URL and instructs the user to install manually. Downloads to `C:\ProgramData\prinstall\staging\`, extracts, stages INF via `pnputil /add-driver *.inf /install`.

**Note:** Windows Update is not a programmatic driver source. There is no PowerShell cmdlet that queries WU for printer drivers and downloads them. The "Add Printer" wizard does this via internal COM APIs, but those are not exposed. For v1, we rely on the local driver store (which may contain WU-staged drivers from prior installs) and manufacturer downloads. The curated `known_matches.toml` provides the driver name intelligence that WU would have offered.

Download constraints: 60-second timeout per download, 500 MB max file size (warn and skip if exceeded), HTTP errors skip the source and print the URL for manual download.

### 4. PowerShell Executor

Thin wrapper that shells out to PowerShell for Windows printer operations:

```powershell
# Step 1: Create TCP/IP port
Add-PrinterPort -Name "IP_192.168.1.50" -PrinterHostAddress "192.168.1.50"

# Step 2: Install driver
Add-PrinterDriver -Name "HP LaserJet Pro MFP M428f PCL-6 (V4)"

# Step 3: Create printer queue
Add-Printer -Name "HP M428fdw" -DriverName "HP LaserJet Pro MFP M428f PCL-6 (V4)" -PortName "IP_192.168.1.50"
```

Each step validates before proceeding. Existing ports/drivers are skipped, not duplicated. Printer display name defaults to the SNMP model string as-is, overridable via `--name`.

**Error handling:** If any step fails, the tool reports which step failed and why (the PowerShell error message). Orphaned ports or staged drivers from partial installs are left in place (harmless) rather than attempting rollback. Exit code 0 on success, 1 on failure.

**Privilege handling:** The binary embeds a UAC manifest (`requireAdministrator`) via the `embed-manifest` build crate. On launch, Windows will prompt for elevation if not already admin. If running through an RMM shell (typically SYSTEM context), elevation is already present. If somehow not elevated, the tool detects this at startup and exits with a clear message.

**Pre-install validation:** Before starting the install flow, SNMP-probe (or ping) the target IP. If unreachable, warn the tech but don't block — the printer may be behind a firewall that drops ICMP/SNMP but still accepts TCP 9100 print traffic. Especially important for the `--model` bypass path where no prior SNMP discovery confirmed reachability.

**Data file packaging:** `drivers.toml` and `known_matches.toml` are embedded in the binary at compile time via `include_str!()`. Single binary, no sidecar files to manage. Updating the data requires a new build. Future version may support a sidecar file at `C:\ProgramData\prinstall\` that overrides embedded defaults.

## Project Structure

```
~/dev/prinstall/
├── Cargo.toml
├── src/
│   ├── main.rs              # Entry point — detect TUI vs CLI
│   ├── cli.rs               # clap subcommands + help text
│   ├── tui/
│   │   ├── mod.rs            # ratatui app loop
│   │   ├── views/            # scan, drivers, install screens
│   │   └── widgets/          # reusable components
│   ├── discovery/
│   │   ├── mod.rs
│   │   ├── snmp.rs           # SNMP queries
│   │   └── subnet.rs         # subnet scanning
│   ├── drivers/
│   │   ├── mod.rs
│   │   ├── matcher.rs        # model string → driver matching
│   │   ├── local_store.rs     # local driver store enumeration (pnputil)
│   │   ├── downloader.rs     # manufacturer downloads
│   │   └── manifest.rs       # drivers.toml parsing
│   ├── installer/
│   │   ├── mod.rs
│   │   └── powershell.rs     # PS cmdlet execution
│   └── models.rs             # shared types (Printer, Driver, etc.)
├── data/
│   ├── drivers.toml          # manufacturer → URL mappings
│   └── known_matches.toml    # curated model → driver mappings
└── README.md
```

## Key Dependencies

| Crate | Purpose |
|-------|---------|
| `ratatui` + `crossterm` | TUI rendering |
| `clap` | CLI parsing with rich help |
| `tokio` | Async runtime (subnet scan, downloads) |
| `reqwest` | HTTP downloads |
| `csnmp` | Async SNMP v1/v2c (tokio-native) |
| `serde` + `toml` | Config/manifest parsing |
| `fuzzy-matcher` | Driver name matching |
| `embed-manifest` | UAC manifest embedding (build dep) |

## Future (out of scope for v1)

- Printer defaults (duplex, color/mono, paper size, default printer)
- mDNS / WS-Discovery for printers with SNMP disabled
- Shared match database across fleet (phone-home)
- Batch install mode (multiple printers from a config file)

## Requirements

- Windows 10 version 1809+
- PowerShell 5.1+ (ships with Windows)
- Administrator privileges (driver installation requires elevation)
- Network access to target printers (UDP 161 for SNMP)
