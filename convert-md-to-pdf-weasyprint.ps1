#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Converts Markdown (.md) files to PDF format using WeasyPrint.

.DESCRIPTION
    This script converts one or more Markdown files to PDF using Pandoc and WeasyPrint.
    WeasyPrint provides excellent CSS support and emoji rendering.

.PARAMETER InputPath
    Path to the markdown file or directory containing markdown files.

.PARAMETER OutputPath
    Optional output directory for PDF files. If not specified, PDFs are created in the same directory as the input files.

.PARAMETER Recursive
    If specified, processes all .md files in subdirectories recursively.

.EXAMPLE
    .\convert-md-to-pdf-weasyprint.ps1 -InputPath "README.md"
    Converts README.md to README.pdf in the same directory.

.EXAMPLE
    .\convert-md-to-pdf-weasyprint.ps1 -InputPath "docs" -OutputPath "output" -Recursive
    Converts all .md files in the docs directory (and subdirectories) to PDFs in the output directory.

.EXAMPLE
    .\convert-md-to-pdf-weasyprint.ps1 -InputPath "*.md"
    Converts all .md files in the current directory to PDFs.
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputPath,

    [Parameter(Mandatory=$false)]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [switch]$Recursive
)

# Get paths to bundled executables
function Get-BundledPaths {
    param([string]$ScriptDir)

    return @{
        Pandoc = Join-Path $ScriptDir "pandoc\pandoc.exe"
        WeasyPrint = Join-Path $ScriptDir "weasyprint\weasyprint.exe"
    }
}

# Check if bundled tools exist
function Test-BundledToolsExist {
    param([hashtable]$Paths)

    $pandocExists = Test-Path $Paths.Pandoc
    $weasyprintExists = Test-Path $Paths.WeasyPrint

    if (-not $pandocExists) {
        Write-Host "Error: Bundled pandoc.exe not found at $($Paths.Pandoc)" -ForegroundColor Red
    }
    if (-not $weasyprintExists) {
        Write-Host "Error: Bundled weasyprint.exe not found at $($Paths.WeasyPrint)" -ForegroundColor Red
    }

    return ($pandocExists -and $weasyprintExists)
}

# Convert a single markdown file to PDF
function Convert-MarkdownToPdf {
    param(
        [string]$MarkdownFile,
        [string]$OutputDir,
        [string]$ScriptDir,
        [hashtable]$ToolPaths
    )

    # Get file names
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($MarkdownFile)
    $htmlFile = Join-Path $OutputDir "$fileName.html"
    $pdfFile = Join-Path $OutputDir "$fileName.pdf"

    # CSS files
    $CssFile = Join-Path $ScriptDir "style.css"
    $PrintCssFile = Join-Path $ScriptDir "weasyprint-style.css"

    Write-Host "Converting: $MarkdownFile -> $pdfFile" -ForegroundColor Cyan

    try {
        # Step 1: Convert Markdown to HTML with embedded CSS
        Write-Host "  Step 1: Creating HTML with embedded CSS..." -ForegroundColor Gray

        if (Test-Path $CssFile) {
            & $ToolPaths.Pandoc $MarkdownFile -f gfm -o $htmlFile --css=$CssFile --standalone --embed-resources
        } else {
            Write-Host "  Warning: CSS file not found at $CssFile, creating HTML without custom styling" -ForegroundColor Yellow
            & $ToolPaths.Pandoc $MarkdownFile -f gfm -o $htmlFile --standalone --embed-resources
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Error: Pandoc failed to create HTML" -ForegroundColor Red
            return $false
        }

        # Step 2: Convert HTML to PDF using WeasyPrint
        Write-Host "  Step 2: Converting HTML to PDF with WeasyPrint..." -ForegroundColor Gray

        $weasyprintArgs = @($htmlFile, $pdfFile, "--quiet")

        # Add print-specific CSS if it exists (for page numbers, etc.)
        if (Test-Path $PrintCssFile) {
            $weasyprintArgs += @("--stylesheet", $PrintCssFile)
        }

        & $ToolPaths.WeasyPrint @weasyprintArgs

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Success: Created $pdfFile" -ForegroundColor Green

            # Clean up intermediate HTML file
            Write-Host "  Step 3: Cleaning up intermediate HTML file..." -ForegroundColor Gray
            Remove-Item $htmlFile -ErrorAction SilentlyContinue

            return $true
        }
        else {
            Write-Host "  Error: WeasyPrint failed to create PDF" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main script logic
try {
    # Get the directory where the script is located
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $ScriptDir) {
        $ScriptDir = Get-Location
    }

    # Get bundled tool paths
    $ToolPaths = Get-BundledPaths -ScriptDir $ScriptDir

    # Check if bundled tools exist
    if (-not (Test-BundledToolsExist -Paths $ToolPaths)) {
        Write-Host ""
        Write-Host "Bundled tools not found. Ensure the following structure:" -ForegroundColor Yellow
        Write-Host "  doc_exporter/" -ForegroundColor Yellow
        Write-Host "    pandoc/pandoc.exe" -ForegroundColor Yellow
        Write-Host "    weasyprint/weasyprint.exe" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Using bundled tools:" -ForegroundColor Gray
    Write-Host "  Pandoc: $($ToolPaths.Pandoc)" -ForegroundColor Gray
    Write-Host "  WeasyPrint: $($ToolPaths.WeasyPrint)" -ForegroundColor Gray
    Write-Host ""

    # Resolve input path
    $resolvedInputPath = Resolve-Path $InputPath -ErrorAction Stop

    # Determine if input is a file or directory
    if (Test-Path $resolvedInputPath -PathType Leaf) {
        # Single file - use Get-Item to get FileInfo object with .FullName
        $markdownFiles = @(Get-Item $resolvedInputPath)
    }
    elseif (Test-Path $resolvedInputPath -PathType Container) {
        # Directory
        if ($Recursive) {
            $markdownFiles = Get-ChildItem -Path $resolvedInputPath -Filter "*.md" -Recurse -File
        }
        else {
            $markdownFiles = Get-ChildItem -Path $resolvedInputPath -Filter "*.md" -File
        }
    }
    else {
        # Try as a wildcard pattern
        $markdownFiles = Get-ChildItem -Path $InputPath -File
    }

    if ($markdownFiles.Count -eq 0) {
        Write-Host "No markdown files found at: $InputPath" -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Found $($markdownFiles.Count) markdown file(s) to convert" -ForegroundColor Cyan
    Write-Host ""

    # Determine output directory
    $outputDir = if ($OutputPath) {
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        Resolve-Path $OutputPath
    }
    else {
        $null
    }

    # Convert each file
    $successCount = 0
    $failCount = 0

    foreach ($file in $markdownFiles) {
        $outDir = if ($outputDir) {
            $outputDir
        }
        else {
            Split-Path $file.FullName -Parent
        }

        if (Convert-MarkdownToPdf -MarkdownFile $file.FullName -OutputDir $outDir -ScriptDir $ScriptDir -ToolPaths $ToolPaths) {
            $successCount++
        }
        else {
            $failCount++
        }
    }

    # Summary
    Write-Host ""
    Write-Host "Conversion complete!" -ForegroundColor Cyan
    Write-Host "  Successful: $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "  Failed: $failCount" -ForegroundColor Red
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
