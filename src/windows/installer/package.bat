@echo off
REM Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
REM SPDX-License-Identifier: BSD-3-Clause
REM
REM Build the self-extracting installer EXE.
REM   1. Compiles the installer using CMake + MSVC
REM   2. Creates a ZIP of all INF + CAT driver files
REM   3. Appends the ZIP payload to the EXE with a trailer
REM
REM Prerequisites:
REM   - CMake and Visual Studio (or MSVC Build Tools)
REM   - Python 3 (for packaging step)
REM   - Run build.bat first to generate .cat files
REM
REM Usage: package.bat
REM Output: qcom-usb-userspace-drivers_<version>.exe (in current directory)

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0\"
set "DRIVER_DIR=%SCRIPT_DIR%.."
set "BUILD_DIR=%SCRIPT_DIR%build"

echo ==========================================
echo  Qualcomm USB Driver Installer Packager
echo ==========================================
echo.

REM Step 1: Build the installer EXE
echo [1/3] Building installer EXE...
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
cmake -B "%BUILD_DIR%" -S "%SCRIPT_DIR%" -G "Visual Studio 16 2019" -A x64
if errorlevel 1 (
    echo ERROR: CMake configure failed
    exit /b 1
)
cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 (
    echo ERROR: CMake build failed
    exit /b 1
)
echo.

REM Step 2-3: Create ZIP and append payload using Python
echo [2/3] Packaging driver files...
echo [3/3] Appending payload to EXE...
REM package.py reads version from version.h and auto-generates output filename
python "%SCRIPT_DIR%package.py" "%BUILD_DIR%\Release\qcom-usb-userspace-drivers.exe" "%DRIVER_DIR%"
if errorlevel 1 (
    echo ERROR: Packaging failed
    exit /b 1
)

echo.
echo ==========================================
echo  SUCCESS: Installer packaged
echo ==========================================