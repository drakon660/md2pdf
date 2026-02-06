#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Converts Markdown (.md) files to PDF format.

.DESCRIPTION
    This script converts one or more Markdown files to PDF using Pandoc.
    Pandoc must be installed on your system for this script to work.

    Install Pandoc: https://pandoc.org/installing.html
    Or via chocolatey: choco install pandoc
    Or via winget: winget install JohnMacFarlane.Pandoc

.PARAMETER InputPath
    Path to the markdown file or directory containing markdown files.

.PARAMETER OutputPath
    Optional output directory for PDF files. If not specified, PDFs are created in the same directory as the input files.

.PARAMETER Recursive
    If specified, processes all .md files in subdirectories recursively.

.EXAMPLE
    .\convert-md-to-pdf.ps1 -InputPath "README.md"
    Converts README.md to README.pdf in the same directory.

.EXAMPLE
    .\convert-md-to-pdf.ps1 -InputPath "docs" -OutputPath "output" -Recursive
    Converts all .md files in the docs directory (and subdirectories) to PDFs in the output directory.

.EXAMPLE
    .\convert-md-to-pdf.ps1 -InputPath "*.md"
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

# Check if Pandoc is installed
function Test-PandocInstalled {
    try {
        $null = Get-Command pandoc -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Convert a single markdown file to PDF
function Convert-MarkdownToPdf {
    param(
        [string]$MarkdownFile,
        [string]$OutputDir,
        [string]$ScriptDir
    )

    # Get file names
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($MarkdownFile)
    $htmlFile = Join-Path $OutputDir "$fileName.html"
    $pdfFile = Join-Path $OutputDir "$fileName.pdf"

    # CSS and footer files are in the script directory (ChatStates/)
    $CssFile = Join-Path $ScriptDir "style.css"
    $FooterFile = Join-Path $ScriptDir "footer.html"

    Write-Host "Converting: $MarkdownFile -> $pdfFile" -ForegroundColor Cyan

    try {
        # Step 1: Convert Markdown to HTML with embedded CSS
        Write-Host "  Step 1: Creating HTML with embedded CSS..." -ForegroundColor Gray

        if (Test-Path $CssFile) {
            pandoc $MarkdownFile -o $htmlFile --css=$CssFile --standalone --self-contained
        } else {
            Write-Host "  Warning: CSS file not found at $CssFile, creating HTML without custom styling" -ForegroundColor Yellow
            pandoc $MarkdownFile -o $htmlFile --standalone --self-contained
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Error: Pandoc failed to create HTML" -ForegroundColor Red
            return $false
        }

        # Step 2: Convert HTML to PDF with page numbers
        Write-Host "  Step 2: Converting HTML to PDF with page numbers..." -ForegroundColor Gray
        
        wkhtmltopdf `
            --enable-local-file-access `
            --footer-center "Page [page] of [topage]" `
            --footer-font-size 9 `
            --margin-bottom 25mm `
            --margin-top 20mm `
            --margin-left 25mm `
            --margin-right 25mm `
            $htmlFile `
            $pdfFile

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Success: Created $pdfFile" -ForegroundColor Green

            # Clean up intermediate HTML file
            Write-Host "  Step 3: Cleaning up intermediate HTML file..." -ForegroundColor Gray
            Remove-Item $htmlFile -ErrorAction SilentlyContinue

            return $true
        }
        else {
            Write-Host "  Error: wkhtmltopdf failed to create PDF" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Example usage:
# Convert-MarkdownToPdf -MarkdownFile "md/ARCHITECTURE.md" -OutputDir "." -ScriptDir "."

# Main script logic
try {
    # Get the directory where the script is located
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $ScriptDir) {
        $ScriptDir = Get-Location
    }
    # Check if Pandoc is installed
    if (-not (Test-PandocInstalled)) {
        Write-Host "Error: Pandoc is not installed!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please install Pandoc first:" -ForegroundColor Yellow
        Write-Host "  - Download from: https://pandoc.org/installing.html" -ForegroundColor Yellow
        Write-Host "  - Or via Chocolatey: choco install pandoc" -ForegroundColor Yellow
        Write-Host "  - Or via Winget: winget install JohnMacFarlane.Pandoc" -ForegroundColor Yellow
        exit 1
    }

    # Resolve input path
    $resolvedInputPath = Resolve-Path $InputPath -ErrorAction Stop

    # Determine if input is a file or directory
    if (Test-Path $resolvedInputPath -PathType Leaf) {
        # Single file
        $markdownFiles = @($resolvedInputPath)
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

        if (Convert-MarkdownToPdf -MarkdownFile $file.FullName -OutputDir $outDir -ScriptDir $ScriptDir) {
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
