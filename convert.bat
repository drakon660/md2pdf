@echo off
REM Wrapper script to run convert-md-to-pdf-weasyprint.ps1 with proper execution policy
REM Usage: convert.bat <input.md> [output_dir] [-Recursive] [-KeepTempFiles]

setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%convert-md-to-pdf-weasyprint.ps1"

if "%~1"=="" (
    echo Usage: convert.bat ^<input.md^> [output_dir] [-Recursive] [-KeepTempFiles]
    echo.
    echo Examples:
    echo   convert.bat README.md
    echo   convert.bat docs\ output\ -Recursive
    echo   convert.bat file.md -KeepTempFiles
    exit /b 1
)

powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
