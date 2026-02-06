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
    [switch]$Recursive,

    [Parameter(Mandatory=$false)]
    [switch]$KeepTempFiles
)

# Get paths to bundled executables
function Get-BundledPaths {
    param([string]$ScriptDir)

    $paths = @{
        Pandoc = Join-Path $ScriptDir "pandoc\pandoc.exe"
        WeasyPrint = Join-Path $ScriptDir "weasyprint\weasyprint.exe"
        Mmdc = $null
    }

    # Look for mmdc (mermaid-cli): local node_modules or system PATH
    $bundledMmdc = Join-Path $ScriptDir "node_modules\.bin\mmdc.cmd"

    if (Test-Path $bundledMmdc) {
        $paths.Mmdc = $bundledMmdc
    }
    elseif (Get-Command "mmdc" -ErrorAction SilentlyContinue) {
        $paths.Mmdc = "mmdc"
    }

    return $paths
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

# Post-process HTML: render Mermaid code blocks to PNG and replace in HTML
function Convert-MermaidInHtml {
    param(
        [string]$HtmlFile,
        [string]$MmdcPath,
        [bool]$KeepTemp = $false
    )

    $html = Get-Content $HtmlFile -Raw -Encoding UTF8
    $pattern = '(?ms)<pre class="mermaid"><code>(.*?)</code></pre>'
    $htmlMatches = [regex]::Matches($html, $pattern)

    if ($htmlMatches.Count -eq 0) {
        return
    }

    if (-not $MmdcPath) {
        Write-Host "  Error: Mermaid blocks found but mmdc (mermaid-cli) is not available." -ForegroundColor Red
        Write-Host "  Install with: npm install -g @mermaid-js/mermaid-cli" -ForegroundColor Red
        throw "mmdc not found - cannot render Mermaid diagrams"
    }

    Write-Host "  Rendering $($htmlMatches.Count) Mermaid diagram(s)..." -ForegroundColor Gray

    $tempDir = Join-Path ([System.IO.Path]::GetDirectoryName($HtmlFile)) "mermaid-temp"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    $index = 0
    foreach ($m in $htmlMatches) {
        $index++
        $mermaidCode = [System.Web.HttpUtility]::HtmlDecode($m.Groups[1].Value)
        $mmdFile = Join-Path $tempDir "diagram-$index.mmd"
        $pngFile = Join-Path $tempDir "diagram-$index.png"

        Set-Content -Path $mmdFile -Value $mermaidCode -Encoding UTF8 -NoNewline

        # mmdc: -i input -o output -b background
        & $MmdcPath -i $mmdFile -o $pngFile -b white --quiet 2>$null

        if (($LASTEXITCODE -eq 0) -and (Test-Path $pngFile)) {
            $pngBytes = [System.IO.File]::ReadAllBytes($pngFile)
            $base64 = [System.Convert]::ToBase64String($pngBytes)
            $imgTag = "<img src=`"data:image/png;base64,$base64`" alt=`"Mermaid diagram`" style=`"max-width:450px; display:block; margin:1em auto`" />"
            $html = $html.Replace($m.Value, $imgTag)
        }
        else {
            Write-Host "    Warning: Failed to render Mermaid diagram $index" -ForegroundColor Yellow
        }
    }

    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8 -NoNewline
    if ($KeepTemp) {
        Write-Host "  Debug: Mermaid temp files kept at $tempDir" -ForegroundColor Magenta
    }
    else {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
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

        # Step 1.5: Render Mermaid diagrams in HTML (if mmdc is available)
        Convert-MermaidInHtml -HtmlFile $htmlFile -MmdcPath $ToolPaths.Mmdc -KeepTemp $KeepTempFiles

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
            if ($KeepTempFiles) {
                Write-Host "  Debug: HTML kept at $htmlFile" -ForegroundColor Magenta
            }
            else {
                Write-Host "  Step 3: Cleaning up intermediate HTML file..." -ForegroundColor Gray
                Remove-Item $htmlFile -ErrorAction SilentlyContinue
            }

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
    if ($ToolPaths.Mmdc) {
        Write-Host "  Mermaid (mmdc): $($ToolPaths.Mmdc)" -ForegroundColor Gray
    }
    else {
        Write-Host "  Mermaid (mmdc): Not found (install with: npm install -g @mermaid-js/mermaid-cli)" -ForegroundColor DarkYellow
    }
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
