# SnapSetup-ui.ps1
# GUI wrapper for SnapSetup.ps1
# Provides a Windows Forms interface for converting project folders into setup scripts.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =============================================================================
# CORE CONVERSION LOGIC (embedded from SnapSetup.ps1)
# =============================================================================

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

function Format-FileSize([long]$bytes) {
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Test-ShouldExcludeFile {
    param(
        [System.IO.FileInfo]$File,
        [string]$RelPath,
        [string[]]$AllPatterns,
        [long]$MaxSize
    )
    $parts = $RelPath -split "[/\\]"
    foreach ($part in $parts) {
        if ($DefaultExcludeFolders -contains $part) { return $true }
    }
    foreach ($pattern in $AllPatterns) {
        if ($File.Name -like $pattern) { return $true }
        if ($RelPath -like $pattern) { return $true }
    }
    if ($File.Length -gt $MaxSize) { return $true }
    return $false
}

function Test-IsBinaryFile([string]$FilePath) {
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    return $BinaryExtensions -contains $ext
}

function Invoke-ProjectConversion {
    param(
        [string]$SourcePath,
        [string]$OutputDir,
        [string]$ProjectName,
        [string[]]$ExcludePatterns,
        [double]$MaxFileSizeMB,
        [System.Windows.Forms.TextBox]$LogBox
    )

    $ErrorActionPreference = "Stop"

    # Helper to append log text
    $appendLog = {
        param([string]$msg)
        $LogBox.AppendText("$msg`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }

    try {
        # --- Validate ---
        if (-not $SourcePath -or -not (Test-Path $SourcePath -PathType Container)) {
            & $appendLog "[ERROR] Source path is not a valid directory: $SourcePath"
            return
        }
        $SourcePath = (Resolve-Path $SourcePath).Path

        if (-not $ProjectName) {
            $ProjectName = Split-Path $SourcePath -Leaf
        }

        if (-not $OutputDir) { $OutputDir = "." }
        if (-not (Test-Path $OutputDir -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        $OutputDir = (Resolve-Path $OutputDir).Path

        $MaxFileSize = [long]($MaxFileSizeMB * 1024 * 1024)
        $WarnSizeMB = 5

        # --- Build exclusion list ---
        $AllExcludePatterns = $DefaultExcludeFiles
        if ($ExcludePatterns -and $ExcludePatterns.Count -gt 0) {
            $AllExcludePatterns = $AllExcludePatterns + $ExcludePatterns
        }

        # --- Scan ---
        & $appendLog "=== Scanning project: $SourcePath ==="

        $allFiles = Get-ChildItem -Path $SourcePath -Recurse -File -Force
        $includedFiles = @()
        $skippedFiles = @()
        $textCount = 0
        $binaryCount = 0
        $totalSize = [long]0

        foreach ($file in $allFiles) {
            $relPath = $file.FullName.Substring($SourcePath.Length + 1) -replace "\\", "/"
            if (Test-ShouldExcludeFile -File $file -RelPath $relPath -AllPatterns $AllExcludePatterns -MaxSize $MaxFileSize) {
                $skippedFiles += $relPath
                continue
            }
            $isBin = Test-IsBinaryFile -FilePath $file.FullName
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
                if ($dirs -notcontains $normalized) { $dirs += $normalized }
            }
        }
        $dirs = $dirs | Sort-Object

        & $appendLog "  Files included : $($includedFiles.Count) ($textCount text, $binaryCount binary)"
        & $appendLog "  Files skipped  : $($skippedFiles.Count)"
        & $appendLog "  Total size     : $(Format-FileSize $totalSize)"
        & $appendLog ""

        if ($includedFiles.Count -eq 0) {
            & $appendLog "[WARN] No files to process. Check source path and exclusion patterns."
            return
        }

        # =====================================================================
        # GENERATE setup.ps1
        # =====================================================================
        & $appendLog "Generating setup.ps1 ..."

        $ps1Lines = [System.Collections.Generic.List[string]]::new()
        $ps1Lines.Add("# setup.ps1 - Auto-generated project setup for Windows (PowerShell 5.1+)")
        $ps1Lines.Add("# Project: $ProjectName")
        $ps1Lines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $ps1Lines.Add("# Files: $($includedFiles.Count) | Size: $(Format-FileSize $totalSize)")
        $ps1Lines.Add("#")
        $ps1Lines.Add("# Usage: powershell -ExecutionPolicy Bypass -File setup.ps1")
        $ps1Lines.Add("")
        $ps1Lines.Add('$root = Join-Path $PSScriptRoot "' + $ProjectName + '"')
        $ps1Lines.Add('Write-Host "`nSetting up project: ' + $ProjectName + '" -ForegroundColor Cyan')
        $ps1Lines.Add('Write-Host "Target: $root`n"')
        $ps1Lines.Add("")

        # Directories
        $ps1Lines.Add("# --- Create directories ---")
        $ps1Lines.Add('New-Item -ItemType Directory -Path $root -Force | Out-Null')
        foreach ($dir in $dirs) {
            $winDir = $dir -replace "/", "\"
            $ps1Lines.Add('New-Item -ItemType Directory -Path (Join-Path $root "' + $winDir + '") -Force | Out-Null')
        }
        $ps1Lines.Add("")

        # Helper function before file writes
        $ps1Lines.Add("# --- Helper ---")
        $ps1Lines.Add('function Format-Size([long]$bytes) {')
        $ps1Lines.Add('    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }')
        $ps1Lines.Add('    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }')
        $ps1Lines.Add('    return "$bytes B"')
        $ps1Lines.Add('}')
        $ps1Lines.Add("")

        # Files
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

        # Summary
        $ps1Lines.Add("# --- Summary ---")
        $ps1Lines.Add('Write-Host "`n=== Setup complete ===" -ForegroundColor Green')
        $ps1Lines.Add('Write-Host "  Project : ' + $ProjectName + '"')
        $ps1Lines.Add('Write-Host "  Files   : $fileCount"')
        $ps1Lines.Add('Write-Host "  Size    : $(Format-Size $totalBytes)"')
        $ps1Lines.Add('Write-Host "  Location: $root`n"')

        # Write setup.ps1 (CRLF, UTF-8 no BOM)
        $ps1Path = Join-Path $OutputDir "setup.ps1"
        $ps1Content = $ps1Lines -join "`r`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($ps1Path, $ps1Content, $utf8NoBom)

        $ps1Size = (Get-Item $ps1Path).Length
        & $appendLog "  => setup.ps1 written: $(Format-FileSize $ps1Size)"

        # =====================================================================
        # GENERATE setup.sh
        # =====================================================================
        & $appendLog "Generating setup.sh ..."

        $shLines = [System.Collections.Generic.List[string]]::new()
        $shLines.Add("#!/bin/bash")
        $shLines.Add("# setup.sh - Auto-generated project setup for Termux / Linux / macOS")
        $shLines.Add("# Project: $ProjectName")
        $shLines.Add("# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $shLines.Add("# Files: $($includedFiles.Count) | Size: $(Format-FileSize $totalSize)")
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

        # Directories
        $shLines.Add("# --- Create directories ---")
        $shLines.Add('mkdir -p "$ROOT"')
        foreach ($dir in $dirs) {
            $shLines.Add('mkdir -p "$ROOT/' + $dir + '"')
        }
        $shLines.Add("")

        # Files
        $shLines.Add("# --- Create files ---")
        $shLines.Add("FILE_COUNT=0")
        $shLines.Add("TOTAL_BYTES=0")
        $shLines.Add("")

        $eofIndex = 0
        foreach ($f in $includedFiles) {
            $shLines.Add("# File: $($f.RelPath)")

            if ($f.IsBinary) {
                $bytes = [System.IO.File]::ReadAllBytes($f.FullPath)
                $b64 = [Convert]::ToBase64String($bytes)
                $shLines.Add('echo "  Creating: ' + $f.RelPath + ' (binary)"')
                $shLines.Add("printf '%s' '$b64' | base64 -d > " + '"$ROOT/' + $f.RelPath + '"')
            }
            else {
                $eofIndex++
                $marker = "SETUPEOF_${eofIndex}"
                $textContent = [System.IO.File]::ReadAllText($f.FullPath)
                while ($textContent.Contains($marker)) {
                    $eofIndex++
                    $marker = "SETUPEOF_${eofIndex}"
                }
                $shLines.Add('echo "  Creating: ' + $f.RelPath + '"')
                $shLines.Add("cat << '$marker' > " + '"$ROOT/' + $f.RelPath + '"')
                $contentLines = $textContent -split "`r?`n"
                foreach ($line in $contentLines) { $shLines.Add($line) }
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

        # Write setup.sh (LF, UTF-8 no BOM)
        $shPath = Join-Path $OutputDir "setup.sh"
        $shContent = $shLines -join "`n"
        [System.IO.File]::WriteAllText($shPath, $shContent, $utf8NoBom)

        $shSize = (Get-Item $shPath).Length
        & $appendLog "  => setup.sh  written: $(Format-FileSize $shSize)"
        & $appendLog ""

        # Warnings
        if ($ps1Size -gt ($WarnSizeMB * 1MB)) {
            & $appendLog "[WARN] setup.ps1 is $(Format-FileSize $ps1Size) - may exceed Google Docs limits (>$WarnSizeMB MB)."
        }
        if ($shSize -gt ($WarnSizeMB * 1MB)) {
            & $appendLog "[WARN] setup.sh is $(Format-FileSize $shSize) - may exceed Google Docs limits (>$WarnSizeMB MB)."
        }

        & $appendLog "=== Done ==="
        & $appendLog "  setup.ps1 : $(Format-FileSize $ps1Size)  ->  $ps1Path"
        & $appendLog "  setup.sh  : $(Format-FileSize $shSize)  ->  $shPath"

        [System.Windows.Forms.MessageBox]::Show(
            "Generation complete!`n`nsetup.ps1: $(Format-FileSize $ps1Size)`nsetup.sh:  $(Format-FileSize $shSize)`n`nOutput: $OutputDir",
            "Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        & $appendLog "[ERROR] $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Error: $($_.Exception.Message)",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

# =============================================================================
# BUILD THE UI
# =============================================================================

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Colors & Fonts ---
$bgDark      = [System.Drawing.Color]::FromArgb(30, 30, 30)
$bgPanel     = [System.Drawing.Color]::FromArgb(45, 45, 48)
$bgInput     = [System.Drawing.Color]::FromArgb(60, 63, 65)
$fgText      = [System.Drawing.Color]::FromArgb(220, 220, 220)
$fgLabel     = [System.Drawing.Color]::FromArgb(180, 180, 180)
$fgAccent    = [System.Drawing.Color]::FromArgb(0, 122, 204)
$fgSuccess   = [System.Drawing.Color]::FromArgb(78, 201, 176)
$btnBg       = [System.Drawing.Color]::FromArgb(0, 122, 204)
$btnHover    = [System.Drawing.Color]::FromArgb(28, 151, 234)
$btnBrowse   = [System.Drawing.Color]::FromArgb(70, 73, 75)
$borderColor = [System.Drawing.Color]::FromArgb(67, 67, 70)

$fontRegular = New-Object System.Drawing.Font("Segoe UI", 9.5)
$fontBold    = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$fontTitle   = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$fontMono    = New-Object System.Drawing.Font("Cascadia Mono,Consolas", 9)

# --- Main Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "SnapSetup"
$form.Size = New-Object System.Drawing.Size(700, 720)
$form.StartPosition = "CenterScreen"
$form.BackColor = $bgDark
$form.ForeColor = $fgText
$form.Font = $fontRegular
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.MinimizeBox = $true

# --- Title ---
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "SnapSetup"
$lblTitle.Font = $fontTitle
$lblTitle.ForeColor = $fgAccent
$lblTitle.Location = New-Object System.Drawing.Point(24, 16)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text = "Convert any project folder into self-contained setup.ps1 + setup.sh"
$lblSubtitle.ForeColor = $fgLabel
$lblSubtitle.Location = New-Object System.Drawing.Point(26, 46)
$lblSubtitle.AutoSize = $true
$form.Controls.Add($lblSubtitle)

# Separator line
$sep1 = New-Object System.Windows.Forms.Label
$sep1.BorderStyle = "Fixed3D"
$sep1.Location = New-Object System.Drawing.Point(24, 72)
$sep1.Size = New-Object System.Drawing.Size(640, 2)
$form.Controls.Add($sep1)

# --- Helper: create a styled label ---
function New-StyledLabel([string]$text, [int]$x, [int]$y) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.ForeColor = $fgLabel
    $lbl.Font = $fontBold
    $lbl.Location = New-Object System.Drawing.Point($x, $y)
    $lbl.AutoSize = $true
    return $lbl
}

# --- Helper: create a styled textbox ---
function New-StyledTextBox([int]$x, [int]$y, [int]$width) {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point($x, $y)
    $tb.Size = New-Object System.Drawing.Size($width, 28)
    $tb.BackColor = $bgInput
    $tb.ForeColor = $fgText
    $tb.BorderStyle = "FixedSingle"
    $tb.Font = $fontRegular
    return $tb
}

# --- Helper: create a browse button ---
function New-BrowseButton([int]$x, [int]$y) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Browse"
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Size = New-Object System.Drawing.Size(75, 28)
    $btn.FlatStyle = "Flat"
    $btn.BackColor = $btnBrowse
    $btn.ForeColor = $fgText
    $btn.FlatAppearance.BorderColor = $borderColor
    $btn.Cursor = "Hand"
    return $btn
}

$yPos = 86

# --- Source Path ---
$lblSource = New-StyledLabel "Source Folder" 24 $yPos
$form.Controls.Add($lblSource)
$yPos += 22

$txtSource = New-StyledTextBox 24 $yPos 545
$form.Controls.Add($txtSource)

$btnSourceBrowse = New-BrowseButton 577 $yPos
$form.Controls.Add($btnSourceBrowse)

$btnSourceBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select the project folder to convert"
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq "OK") {
        $txtSource.Text = $dlg.SelectedPath
        # Auto-fill project name from folder name if empty
        if (-not $txtProjectName.Text) {
            $txtProjectName.Text = Split-Path $dlg.SelectedPath -Leaf
        }
    }
})

$yPos += 40

# --- Output Directory ---
$lblOutput = New-StyledLabel "Output Directory (optional, defaults to current dir)" 24 $yPos
$form.Controls.Add($lblOutput)
$yPos += 22

$txtOutput = New-StyledTextBox 24 $yPos 545
$form.Controls.Add($txtOutput)

$btnOutputBrowse = New-BrowseButton 577 $yPos
$form.Controls.Add($btnOutputBrowse)

$btnOutputBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select output directory"
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq "OK") {
        $txtOutput.Text = $dlg.SelectedPath
    }
})

$yPos += 40

# --- Project Name + Max File Size (side by side) ---
$lblProjectName = New-StyledLabel "Project Name (optional)" 24 $yPos
$form.Controls.Add($lblProjectName)

$lblMaxSize = New-StyledLabel "Max File Size (MB)" 400 $yPos
$form.Controls.Add($lblMaxSize)
$yPos += 22

$txtProjectName = New-StyledTextBox 24 $yPos 350
$form.Controls.Add($txtProjectName)

$txtMaxSize = New-StyledTextBox 400 $yPos 100
$txtMaxSize.Text = "10"
$form.Controls.Add($txtMaxSize)

$yPos += 40

# --- Exclude Patterns ---
$lblExclude = New-StyledLabel "Additional Exclude Patterns (one per line)" 24 $yPos
$form.Controls.Add($lblExclude)
$yPos += 22

$txtExclude = New-Object System.Windows.Forms.TextBox
$txtExclude.Location = New-Object System.Drawing.Point(24, $yPos)
$txtExclude.Size = New-Object System.Drawing.Size(630, 70)
$txtExclude.Multiline = $true
$txtExclude.ScrollBars = "Vertical"
$txtExclude.BackColor = $bgInput
$txtExclude.ForeColor = $fgText
$txtExclude.BorderStyle = "FixedSingle"
$txtExclude.Font = $fontMono
$form.Controls.Add($txtExclude)

$yPos += 78

# Default exclusions hint
$lblDefaults = New-Object System.Windows.Forms.Label
$lblDefaults.Text = "Built-in exclusions: __pycache__, node_modules, .git, .venv, dist, build, *.pyc, *.log, *.tmp, etc."
$lblDefaults.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
$lblDefaults.Location = New-Object System.Drawing.Point(26, $yPos)
$lblDefaults.Size = New-Object System.Drawing.Size(630, 18)
$lblDefaults.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$form.Controls.Add($lblDefaults)

$yPos += 28

# Separator
$sep2 = New-Object System.Windows.Forms.Label
$sep2.BorderStyle = "Fixed3D"
$sep2.Location = New-Object System.Drawing.Point(24, $yPos)
$sep2.Size = New-Object System.Drawing.Size(640, 2)
$form.Controls.Add($sep2)

$yPos += 12

# --- Generate Button ---
$btnGenerate = New-Object System.Windows.Forms.Button
$btnGenerate.Text = "Generate Setup Files"
$btnGenerate.Location = New-Object System.Drawing.Point(24, $yPos)
$btnGenerate.Size = New-Object System.Drawing.Size(630, 40)
$btnGenerate.FlatStyle = "Flat"
$btnGenerate.BackColor = $btnBg
$btnGenerate.ForeColor = [System.Drawing.Color]::White
$btnGenerate.Font = $fontBold
$btnGenerate.FlatAppearance.BorderSize = 0
$btnGenerate.Cursor = "Hand"
$form.Controls.Add($btnGenerate)

# Hover effect
$btnGenerate.Add_MouseEnter({ $btnGenerate.BackColor = $btnHover })
$btnGenerate.Add_MouseLeave({ $btnGenerate.BackColor = $btnBg })

$yPos += 52

# --- Log Output ---
$lblLog = New-StyledLabel "Output" 24 $yPos
$form.Controls.Add($lblLog)
$yPos += 22

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(24, $yPos)
$txtLog.Size = New-Object System.Drawing.Size(630, 185)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Both"
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$txtLog.ForeColor = $fgSuccess
$txtLog.BorderStyle = "FixedSingle"
$txtLog.Font = $fontMono
$txtLog.WordWrap = $false
$form.Controls.Add($txtLog)

# --- Generate Button Click ---
$btnGenerate.Add_Click({
    # Validate source path
    if (-not $txtSource.Text) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a source folder.",
            "Missing Source",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    # Parse max file size
    $maxSizeMB = 10.0
    if ($txtMaxSize.Text) {
        $parsed = 0.0
        if ([double]::TryParse($txtMaxSize.Text, [ref]$parsed)) {
            $maxSizeMB = $parsed
        }
    }

    # Parse exclude patterns (one per line, skip empties)
    $excludes = @()
    if ($txtExclude.Text.Trim()) {
        $excludes = $txtExclude.Text -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }
    }

    # Output dir
    $outDir = $txtOutput.Text
    if (-not $outDir) { $outDir = "." }

    # Clear log
    $txtLog.Clear()

    # Disable UI during generation
    $btnGenerate.Enabled = $false
    $btnGenerate.Text = "Generating..."
    $btnGenerate.BackColor = $borderColor

    try {
        Invoke-ProjectConversion `
            -SourcePath $txtSource.Text `
            -OutputDir $outDir `
            -ProjectName $txtProjectName.Text `
            -ExcludePatterns $excludes `
            -MaxFileSizeMB $maxSizeMB `
            -LogBox $txtLog
    }
    finally {
        $btnGenerate.Enabled = $true
        $btnGenerate.Text = "Generate Setup Files"
        $btnGenerate.BackColor = $btnBg
    }
})

# --- Show Form ---
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

# Cleanup
$form.Dispose()
