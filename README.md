# md2pdf

Markdown to PDF converter using Pandoc and WeasyPrint. Supports Mermaid diagrams.

## Usage

### Using the batch file (recommended)

```batch
convert.bat <input.md> [output_dir] [-Recursive] [-KeepTempFiles]
```

Examples:
```batch
convert.bat README.md
convert.bat docs\ output\ -Recursive
convert.bat file.md -KeepTempFiles
```

### Using PowerShell directly

If you get an execution policy error, use one of these methods:

**Option 1: Run with bypass**
```powershell
powershell -ExecutionPolicy Bypass -File .\convert-md-to-pdf-weasyprint.ps1 -InputPath "file.md"
```

**Option 2: Unblock the downloaded file**
```powershell
Unblock-File .\convert-md-to-pdf-weasyprint.ps1
.\convert-md-to-pdf-weasyprint.ps1 -InputPath "file.md"
```

**Option 3: Change execution policy (permanent)**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-InputPath` | Path to markdown file or directory |
| `-OutputPath` | Optional output directory for PDFs |
| `-Recursive` | Process subdirectories recursively |
| `-KeepTempFiles` | Keep intermediate HTML and mermaid temp files for debugging |

## Features

- Converts Markdown to PDF with custom styling
- Supports GitHub Flavored Markdown (GFM)
- Mermaid diagram rendering (requires `mmdc` / mermaid-cli)
- Batch conversion of multiple files
- Custom CSS styling via `style.css` and `weasyprint-style.css`

## Mermaid Support

To enable Mermaid diagram rendering, install mermaid-cli:

```bash
npm install -g @mermaid-js/mermaid-cli
```

## Requirements

The release package includes:
- `pandoc.exe` - Markdown to HTML conversion
- `weasyprint.exe` - HTML to PDF conversion

Optional:
- `mmdc` (mermaid-cli) - For Mermaid diagram rendering
