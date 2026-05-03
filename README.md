# SnapSetup

**Convert any project folder into self-contained, portable setup scripts.**

SnapSetup scans a project directory and generates two scripts — `setup.ps1` (Windows/PowerShell) and `setup.sh` (macOS/Linux/Bash) — that recreate the full folder structure and all files when run. No zip, no installer, just one script.

---

## Table of Contents

- [Overview](#overview)
- [Tools Included](#tools-included)
- [Quick Start](#quick-start)
- [CLI Tool — project-to-setup.ps1](#cli-tool--project-to-setupps1)
- [GUI Tool — project-to-setup-ui.ps1](#gui-tool--project-to-setup-uips1)
- [Web App — project-to-setup.html](#web-app--project-to-setuphtml)
- [Generated Scripts](#generated-scripts)
- [Default Exclusions](#default-exclusions)
- [Binary File Detection](#binary-file-detection)
- [Technical Details](#technical-details)
- [Troubleshooting](#troubleshooting)

---

## Overview

SnapSetup is a set of three tools (CLI, GUI, and Web) that all do the same thing:

1. Scan a project folder recursively
2. Read every file (text and binary)
3. Generate a **setup.ps1** (PowerShell) and **setup.sh** (Bash) that embed all file contents inline
4. Running either script on a target machine recreates the entire project — no dependencies required

### Use Cases

- Share a project as a single file via email, chat, or docs
- Bootstrap a dev environment on a new machine
- Create portable project snapshots
- Transfer projects to air-gapped systems

---

## Tools Included

| File | Type | Platform | Requirements |
|---|---|---|---|
| `SnapSetup.ps1` | CLI | Windows | PowerShell 5.1+ |
| `SnapSetup.ps1` | GUI (WinForms) | Windows | PowerShell 5.1+ with .NET |
| `index.html` | Web App | Any | Chrome or Edge 86+ |

---

## Quick Start

### CLI

```powershell
.\SnapSetup.ps1 -SourcePath "C:\Projects\MyApp"
```

Generates `setup.ps1` and `setup.sh` in the current directory.

### GUI

```powershell
.\SnapSetup-ui.ps1
```

A dark-themed Windows Forms window opens. Browse for your source folder, configure options, and click **Generate Setup Files**.

### Web App

Open `index.html` in **Chrome** or **Edge**. Click the drop zone to select a folder, then click **Generate Setup Files**.

---

## CLI Tool — SnapSetup.ps1

### Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-SourcePath` | String | Yes | — | Path to the project folder to convert |
| `-OutputDir` | String | No | `.` (current dir) | Directory where generated scripts are saved |
| `-ProjectName` | String | No | Source folder name | Root folder name used in generated scripts |
| `-ExcludePatterns` | String[] | No | `@()` | Additional glob patterns to exclude |
| `-MaxFileSizeMB` | Double | No | `10` | Files above this size (MB) are skipped |

### Examples

**Basic usage:**
```powershell
.\SnapSetup.ps1 -SourcePath "C:\Projects\MyApp"
```

**Custom output directory and project name:**
```powershell
.\SnapSetup.ps1 -SourcePath "C:\Projects\MyApp" -OutputDir "C:\Output" -ProjectName "my-app-v2"
```

**Exclude additional patterns and increase size limit:**
```powershell
.\SnapSetup.ps1 -SourcePath "C:\Projects\MyApp" -ExcludePatterns @("*.env", "secrets/*") -MaxFileSizeMB 25
```

### Output

- `setup.ps1` — PowerShell setup script (CRLF line endings)
- `setup.sh` — Bash setup script (LF line endings)

Both files are encoded as UTF-8 without BOM.

---

## GUI Tool — project-to-setup-ui.ps1

A Windows Forms application with a dark VS Code-style theme.

### Interface

- **Source Folder** — Browse button to select the project directory
- **Output Directory** — Browse button to choose where scripts are saved
- **Project Name** — Auto-populated from the source folder name; editable
- **Max File Size (MB)** — Default: `10`
- **Exclude Patterns** — Multi-line text box, one pattern per line
- **Generate Setup Files** — Starts the conversion process
- **Log Output** — Real-time progress and status messages

### Features

- Dark theme (background `#1E1E1E`, accent `#007ACC`)
- Live log output during generation
- Auto-detection of project name from folder selection
- UI disables during processing to prevent double-runs
- Success/error message dialogs on completion

---

## Web App — project-to-setup.html

A modern, single-file web application (no server required).

### Requirements

- **Chrome 86+** or **Edge 86+** (uses the File System Access API)
- Firefox and Safari are **not supported**

### Features

- **Folder picker** — Click the drop zone or drag & drop a folder
- **Configuration** — Project name, max file size, exclude patterns
- **Real-time progress** — Animated progress bar with scan statistics
- **Output log** — Color-coded log with file-by-file details
- **Copy to Clipboard** — Recommended to avoid Windows Mark of the Web (MOTW) security warnings
- **Download** — Direct `.ps1` and `.sh` file downloads
- **Help modal** — Built-in documentation accessible via the `?` icon
- **Scan statistics** — Total files, text files, binary files, total size, skipped count

### Mark of the Web (MOTW) Tip

Windows flags downloaded files with MOTW, which can block script execution. Two options:

1. **Copy to Clipboard** (recommended) — Paste into a locally-created file; no MOTW
2. **Download** — Right-click the file → Properties → check **Unblock** → OK

---

## Generated Scripts

### setup.ps1 (Windows)

- **Runtime:** PowerShell 5.1+
- **Execution:** `powershell -ExecutionPolicy Bypass -File setup.ps1`
- **Output location:** Creates `.\ProjectName\` relative to the script location
- **Encoding:** All files stored as Base64 strings, decoded via `[Convert]::FromBase64String()`
- **File writing:** `[System.IO.File]::WriteAllBytes()` for byte-perfect output
- **Progress:** Colorized `Write-Host` output with file counter and size summary

### setup.sh (macOS / Linux)

- **Runtime:** Bash
- **Execution:** `chmod +x setup.sh && ./setup.sh`
- **Output location:** Creates `./ProjectName/` relative to the script location
- **Text files:** Embedded via heredoc (`cat << 'SETUPEOF_N'`) with unique collision-safe markers
- **Binary files:** Base64 encoded, decoded inline with `base64 -d`
- **Progress:** Echo output with file counter and formatted size summary using `awk`

---

## Default Exclusions

These are always excluded during scanning:

### Folders

| Folder | Reason |
|---|---|
| `node_modules` | npm dependencies |
| `.git` | Git repository data |
| `__pycache__` | Python bytecode cache |
| `.venv` / `venv` | Python virtual environments |
| `.env` | Environment configuration |
| `dist` / `build` | Build output |
| `.vs` / `.vscode` / `.idea` | IDE configuration |
| `bin` / `obj` | .NET build output |

### File Patterns

| Pattern | Reason |
|---|---|
| `*.pyc` / `*.pyo` | Python compiled files |
| `*.log` | Log files |
| `*.tmp` / `*.bak` | Temporary / backup files |
| `Thumbs.db` | Windows thumbnail cache |
| `.DS_Store` | macOS folder metadata |

You can add additional patterns via the `-ExcludePatterns` parameter (CLI), the exclude patterns text box (GUI/Web).

---

## Binary File Detection

Files with these extensions are treated as binary (Base64-encoded in both output scripts):

| Category | Extensions |
|---|---|
| **Images** | `.png`, `.jpg`, `.jpeg`, `.gif`, `.ico`, `.bmp`, `.svg` |
| **Fonts** | `.woff`, `.woff2`, `.ttf`, `.eot`, `.otf` |
| **Media** | `.mp3`, `.mp4`, `.wav`, `.ogg`, `.webm`, `.avi` |
| **Archives** | `.zip`, `.tar`, `.gz`, `.7z`, `.rar` |
| **Documents** | `.pdf`, `.doc`, `.docx`, `.xls`, `.xlsx` |
| **Binaries** | `.exe`, `.dll`, `.so`, `.dylib`, `.bin`, `.dat`, `.db`, `.sqlite` |

All other files are treated as text.

---

## Technical Details

### Encoding

| Output | Line Endings | Character Encoding | BOM |
|---|---|---|---|
| `setup.ps1` | CRLF (`\r\n`) | UTF-8 | None |
| `setup.sh` | LF (`\n`) | UTF-8 | None |

### Size Warnings

- Files exceeding `MaxFileSizeMB` (default 10 MB) are skipped with a warning
- If a generated script exceeds **5 MB**, a warning is shown about potential issues with Google Docs or other sharing platforms

### File Integrity

- Binary files are preserved byte-for-byte through Base64 encoding/decoding
- Text files in `.sh` use heredocs with collision-safe unique markers
- Text files in `.ps1` use Base64 (same as binary) for consistency

---

## Troubleshooting

### "Running scripts is disabled on this system"

Run in PowerShell:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```
Or run the script with bypass:
```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

### Web app says "Browser not supported"

The File System Access API requires **Chrome 86+** or **Edge 86+**. Firefox and Safari do not support `showDirectoryPicker()`.

### Downloaded script is blocked by Windows

Windows applies Mark of the Web (MOTW) to downloaded files. Either:
1. Use **Copy to Clipboard** in the web app and paste into a locally-created file
2. Right-click the file → **Properties** → check **Unblock** → **OK**

### Generated script is too large

- Reduce the project size by adding more exclude patterns
- Lower the `MaxFileSizeMB` threshold
- Exclude large binary assets

### setup.sh permission denied

```bash
chmod +x setup.sh
./setup.sh
```

---

## Version History

| Version | Changes |
|---|---|
| **2.0** | Modern HTML web app (SnapSetup), WinForms GUI, help documentation |
| **1.0** | Initial CLI tool with PowerShell + Bash generation |

---

## License

Internal tool — not published.
