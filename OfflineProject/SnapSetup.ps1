# SnapSetup.ps1
# Converts a project folder into two self-contained setup scripts:
#   setup.ps1 (Windows) and setup.sh (Termux/Linux/macOS)
# Each generated file fully recreates the project when run on its target platform.

param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [string]$OutputDir = ".",

    [string]$ProjectName,

    [string[]]$ExcludePatterns,

    [double]$MaxFileSizeMB = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Defaults ---

$DefaultExcludeFolders = @(
    "__pycache__", "node_modules", ".git", ".venv", "venv", ".env",
    "dist", "build", ".vs", ".vscode", ".idea", "bin", "obj"
)

$DefaultExcludeFiles = @(
    "*.pyc", "*.pyo", "*.log", "*.tmp", "*.bak", "Thumbs.db", ".DS_Store"
)

$BinaryExtensions = @(
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".bmp", ".svg",
    ".woff", ".woff2", ".ttf", ".eot", ".otf",
    ".mp3", ".mp4", ".wav", ".ogg", ".webm", ".avi",
    ".zip", ".tar", ".gz", ".7z", ".rar",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx",
    ".exe", ".dll", ".so", ".dylib", ".bin",
    ".dat", ".db", ".sqlite"
)

$MaxFileSize = [long]($MaxFileSizeMB * 1024 * 1024)
$WarnSizeMB = 5

# --- Resolve paths ---

$SourcePath = (Resolve-Path $SourcePath).Path
if (-not (Test-Path $SourcePath -PathType Container)) {
    Write-Error "Source path '$SourcePath' is not a valid directory."
    exit 1
}

if (-not $ProjectName) {
    $ProjectName = Split-Path $SourcePath -Leaf
}

if (-not (Test-Path $OutputDir -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$OutputDir = (Resolve-Path $OutputDir).Path

# --- Build exclusion lists ---

# Merge user patterns with defaults
$AllExcludePatterns = $DefaultExcludeFiles
if ($ExcludePatterns) {
    $AllExcludePatterns = $AllExcludePatterns + $ExcludePatterns
}

function Test-ShouldExclude {
    param([System.IO.FileInfo]$File, [string]$RelPath)

    # Check folder exclusions
    $parts = $RelPath -split "[/\\]"
    foreach ($part in $parts) {
        if ($DefaultExcludeFolders -contains $part) { return $true }
    }

    # Check file pattern exclusions
    foreach ($pattern in $AllExcludePatterns) {
        if ($File.Name -like $pattern) { return $true }
        if ($RelPath -like $pattern) { return $true }
    }

    # Check size
    if ($File.Length -gt $MaxFileSize) { return $true }

    return $false
}

function Test-IsBinary {
    param([string]$FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    return $BinaryExtensions -contains $ext
}

# --- Scan files ---

Write-Host "`n=== Scanning project: $SourcePath ===" -ForegroundColor Cyan

$allFiles = Get-ChildItem -Path $SourcePath -Recurse -File -Force
$includedFiles = @()
$skippedFiles = @()
$textCount = 0
$binaryCount = 0
$totalSize = [long]0

foreach ($file in $allFiles) {
    $relPath = $file.FullName.Substring($SourcePath.Length + 1) -replace "\\", "/"
    if (Test-ShouldExclude -File $file -RelPath $relPath) {
        $skippedFiles += $relPath
        continue
    }
    $isBin = Test-IsBinary -FilePath $file.FullName
    $includedFiles += [PSCustomObject]@{
        FullPath = $file.FullName
        RelPath  = $relPath
        IsBinary = $isBin
        Size     = $file.Length
    }
    if ($isBin) { $binaryCount++ } else { $textCount++ }
    $totalSize += $file.Length
}

# Collect unique directories
$dirs = @()
foreach ($f in $includedFiles) {
    $parent = Split-Path $f.RelPath
    if ($parent -and $parent -ne ".") {
        $normalized = $parent -replace "\\", "/"
        if ($dirs -notcontains $normalized) {
            $dirs += $normalized
        }
    }
}
# Sort so parents come before children
$dirs = $dirs | Sort-Object

function Format-Size([long]$bytes) {
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

Write-Host "  Files included : $($includedFiles.Count) ($textCount text, $binaryCount binary)"
Write-Host "  Files skipped  : $($skippedFiles.Count)"
Write-Host "  Total size     : $(Format-Size $totalSize)"
Write-Host ""

if ($includedFiles.Count -eq 0) {
    Write-Warning "No files to process. Check your source path and exclusion patterns."
    exit 0
}

# =============================================================================
# GENERATE setup.ps1 (Windows)
# =============================================================================

Write-Host "Generating setup.ps1 ..." -ForegroundColor Yellow

$ps1Lines = [System.Collections.Generic.List[string]]::new()

$ps1Lines.Add("# setup.ps1 - Auto-generated project setup for Windows (PowerShell 5.1+)")
$ps1Lines.Add("# Project: $ProjectName")
$ps1Lines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$ps1Lines.Add("# Files: $($includedFiles.Count) | Size: $(Format-Size $totalSize)")
$ps1Lines.Add("#")
$ps1Lines.Add("# Usage: powershell -ExecutionPolicy Bypass -File setup.ps1")
$ps1Lines.Add("")
$ps1Lines.Add('$root = Join-Path $PSScriptRoot "' + $ProjectName + '"')
$ps1Lines.Add('Write-Host "`nSetting up project: ' + $ProjectName + '" -ForegroundColor Cyan')
$ps1Lines.Add('Write-Host "Target: $root`n"')
$ps1Lines.Add("")

# Create directories
$ps1Lines.Add("# --- Create directories ---")
$ps1Lines.Add('New-Item -ItemType Directory -Path $root -Force | Out-Null')
foreach ($dir in $dirs) {
    $winDir = $dir -replace "/", "\"
    $ps1Lines.Add('New-Item -ItemType Directory -Path (Join-Path $root "' + $winDir + '") -Force | Out-Null')
}
$ps1Lines.Add("")

# Helper function (must be before file writes that use it)
$ps1Lines.Add("# --- Helper ---")
$ps1Lines.Add('function Format-Size([long]$bytes) {')
$ps1Lines.Add('    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }')
$ps1Lines.Add('    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }')
$ps1Lines.Add('    return "$bytes B"')
$ps1Lines.Add('}')
$ps1Lines.Add("")

# Write files
$ps1Lines.Add("# --- Create files ---")
$ps1Lines.Add('$fileCount = 0')
$ps1Lines.Add('$totalBytes = [long]0')
$ps1Lines.Add("")

foreach ($f in $includedFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullPath)
    $b64 = [Convert]::ToBase64String($bytes)
    $winRel = $f.RelPath -replace "/", "\"

    $ps1Lines.Add("# File: $($f.RelPath)")
    $ps1Lines.Add('$b = [Convert]::FromBase64String("' + $b64 + '")')
    $ps1Lines.Add('$p = Join-Path $root "' + $winRel + '"')
    $ps1Lines.Add('[System.IO.File]::WriteAllBytes($p, $b)')
    $ps1Lines.Add('Write-Host "  Created: ' + $f.RelPath + ' ($(Format-Size $b.Length))"')
    $ps1Lines.Add('$fileCount++')
    $ps1Lines.Add('$totalBytes += $b.Length')
    $ps1Lines.Add("")
}

# Summary footer
$ps1Lines.Add("# --- Summary ---")
$ps1Lines.Add('Write-Host "`n=== Setup complete ===" -ForegroundColor Green')
$ps1Lines.Add('Write-Host "  Project : ' + $ProjectName + '"')
$ps1Lines.Add('Write-Host "  Files   : $fileCount"')
$ps1Lines.Add('Write-Host "  Size    : $(Format-Size $totalBytes)"')
$ps1Lines.Add('Write-Host "  Location: $root`n"')

# Write setup.ps1 with CRLF, UTF-8 no BOM
$ps1Path = Join-Path $OutputDir "setup.ps1"
$ps1Content = $ps1Lines -join "`r`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($ps1Path, $ps1Content, $utf8NoBom)

$ps1Size = (Get-Item $ps1Path).Length
Write-Host "  => setup.ps1 written: $(Format-Size $ps1Size)" -ForegroundColor Green

# =============================================================================
# GENERATE setup.sh (Bash)
# =============================================================================

Write-Host "Generating setup.sh ..." -ForegroundColor Yellow

$shLines = [System.Collections.Generic.List[string]]::new()

$shLines.Add("#!/bin/bash")
$shLines.Add("# setup.sh - Auto-generated project setup for Termux / Linux / macOS")
$shLines.Add("# Project: $ProjectName")
$shLines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$shLines.Add("# Files: $($includedFiles.Count) | Size: $(Format-Size $totalSize)")
$shLines.Add("#")
$shLines.Add("# Usage: bash setup.sh")
$shLines.Add("")
$shLines.Add('SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"')
$shLines.Add('ROOT="$SCRIPT_DIR/' + $ProjectName + '"')
$shLines.Add("")
$shLines.Add('echo ""')
$shLines.Add('echo "Setting up project: ' + $ProjectName + '"')
$shLines.Add('echo "Target: $ROOT"')
$shLines.Add('echo ""')
$shLines.Add("")

# Create directories
$shLines.Add("# --- Create directories ---")
$shLines.Add('mkdir -p "$ROOT"')
foreach ($dir in $dirs) {
    $shLines.Add('mkdir -p "$ROOT/' + $dir + '"')
}
$shLines.Add("")

# Write files
$shLines.Add("# --- Create files ---")
$shLines.Add("FILE_COUNT=0")
$shLines.Add("TOTAL_BYTES=0")
$shLines.Add("")

# EOF marker counter for uniqueness
$eofIndex = 0

foreach ($f in $includedFiles) {
    $shLines.Add("# File: $($f.RelPath)")

    if ($f.IsBinary) {
        # Binary: base64 -d
        $bytes = [System.IO.File]::ReadAllBytes($f.FullPath)
        $b64 = [Convert]::ToBase64String($bytes)
        $shLines.Add('echo "  Creating: ' + $f.RelPath + ' (binary)"')
        # Split long base64 into chunks to avoid line-length issues
        # Use printf to avoid echo interpretation issues
        $shLines.Add("printf '%s' '$b64' | base64 -d > " + '"$ROOT/' + $f.RelPath + '"')
    }
    else {
        # Text: heredoc with unique marker
        $eofIndex++
        $marker = "SETUPEOF_${eofIndex}"

        # Read content and check if marker appears in it
        $textContent = [System.IO.File]::ReadAllText($f.FullPath)
        # Ensure marker is unique w.r.t. file content
        while ($textContent.Contains($marker)) {
            $eofIndex++
            $marker = "SETUPEOF_${eofIndex}"
        }

        $shLines.Add('echo "  Creating: ' + $f.RelPath + '"')
        $shLines.Add("cat << '$marker' > " + '"$ROOT/' + $f.RelPath + '"')

        # Add file content line by line (already using LF join later)
        $contentLines = $textContent -split "`r?`n"
        foreach ($line in $contentLines) {
            $shLines.Add($line)
        }

        $shLines.Add($marker)
    }

    $shLines.Add('FILE_COUNT=$((FILE_COUNT + 1))')
    $shLines.Add('TOTAL_BYTES=$((TOTAL_BYTES + ' + $f.Size.ToString() + '))')
    $shLines.Add("")
}

# Summary
$shLines.Add("# --- Summary ---")
$shLines.Add('format_size() {')
$shLines.Add('    local bytes=$1')
$shLines.Add('    if [ "$bytes" -ge 1048576 ]; then')
$shLines.Add('        echo "$(awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}")"')
$shLines.Add('    elif [ "$bytes" -ge 1024 ]; then')
$shLines.Add('        echo "$(awk "BEGIN {printf \"%.2f KB\", $bytes/1024}")"')
$shLines.Add('    else')
$shLines.Add('        echo "${bytes} B"')
$shLines.Add('    fi')
$shLines.Add('}')
$shLines.Add("")
$shLines.Add('echo ""')
$shLines.Add('echo "=== Setup complete ==="')
$shLines.Add('echo "  Project : ' + $ProjectName + '"')
$shLines.Add('echo "  Files   : $FILE_COUNT"')
$shLines.Add('echo "  Size    : $(format_size $TOTAL_BYTES)"')
$shLines.Add('echo "  Location: $ROOT"')
$shLines.Add('echo ""')

# Write setup.sh with LF, UTF-8 no BOM
$shPath = Join-Path $OutputDir "setup.sh"
$shContent = $shLines -join "`n"
[System.IO.File]::WriteAllText($shPath, $shContent, $utf8NoBom)

$shSize = (Get-Item $shPath).Length
Write-Host "  => setup.sh  written: $(Format-Size $shSize)" -ForegroundColor Green

# =============================================================================
# Final warnings and summary
# =============================================================================

Write-Host ""
if ($ps1Size -gt ($WarnSizeMB * 1MB)) {
    Write-Warning "setup.ps1 is $(Format-Size $ps1Size) — may exceed Google Docs limits (>$WarnSizeMB MB)."
}
if ($shSize -gt ($WarnSizeMB * 1MB)) {
    Write-Warning "setup.sh is $(Format-Size $shSize) — may exceed Google Docs limits (>$WarnSizeMB MB)."
}

Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "  setup.ps1 : $(Format-Size $ps1Size)  ->  $ps1Path"
Write-Host "  setup.sh  : $(Format-Size $shSize)  ->  $shPath"
Write-Host ""
