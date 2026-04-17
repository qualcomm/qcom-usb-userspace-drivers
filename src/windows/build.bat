:: Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
:: SPDX-License-Identifier: BSD-3-Clause

@echo off
setlocal enabledelayedexpansion

:: Build script for generating Windows driver catalog (.cat) files.
::
:: Prerequisites:
::   - Windows Driver Kit (WDK) installed (provides inf2cat.exe)
::
:: Usage:
::   build.bat

set "SCRIPT_DIR=%~dp0\"

:: Locate inf2cat.exe - check PATH first, then search WDK installation (prefer x86 build)
set "INF2CAT=inf2cat"
where inf2cat >nul 2>&1
if %errorlevel% neq 0 (
    set "INF2CAT="
    for /f "delims=" %%i in ('dir /s /b "C:\Program Files (x86)\Windows Kits\10\bin\inf2cat.exe" 2^>nul ^| findstr /i "\\x86\\"') do (
        if not defined INF2CAT set "INF2CAT=%%i"
    )
    if not defined INF2CAT (
        for /f "delims=" %%i in ('dir /s /b "C:\Program Files (x86)\Windows Kits\10\bin\inf2cat.exe" 2^>nul') do (
            if not defined INF2CAT set "INF2CAT=%%i"
        )
    )
    if not defined INF2CAT (
        echo Error: inf2cat.exe not found. Please install the Windows Driver Kit ^(WDK^)
        echo and ensure it is in your PATH, or install it to the default location.
        exit /b 1
    )
    echo Found inf2cat at: !INF2CAT!
)

:: Target OS versions for catalog generation
:: Adjust this list based on your WDK version. Newer WDK versions support 10_ARM64.
set "OS_VERSIONS=10_X64,10_X86"

echo ==========================================
echo  Qualcomm USB Driver Catalog Build Script
echo ==========================================
echo.

:: Generate catalog files for all INF files in the driver directory
echo Generating catalog files...
"!INF2CAT!" /driver:"%SCRIPT_DIR%" /os:%OS_VERSIONS%

if !ERRORLEVEL! NEQ 0 (
    echo.
    echo Failed to generate catalog files ^(Error code !ERRORLEVEL!^)
    exit /b 1
)

echo.
echo Generated catalog files:
for %%f in ("%SCRIPT_DIR%*.cat") do (
    echo   %%~nxf
)

echo.
echo Build completed successfully.
endlocal