:: Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
:: SPDX-License-Identifier: BSD-3-Clause

@echo off
setlocal enabledelayedexpansion

:: Check and ask for admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Get the path where the .bat file is located
set "CURRENT_DIR=%~dp0"

:: Collect the base names of .inf files shipped with this package
set "INF_NAMES="
for %%f in ("%CURRENT_DIR%\*.inf") do (
    set "INF_NAMES=!INF_NAMES! %%~nxf"
)

if "!INF_NAMES!"=="" (
    echo No .inf files found in %CURRENT_DIR%.
    pause
    exit /b 1
)

echo ==========================================================
echo  Qualcomm USB Userspace Driver — Uninstall
echo ==========================================================
echo.
echo This will remove the following driver packages:
echo !INF_NAMES!
echo.

:: Enumerate installed OEM driver packages and remove matches
set "FOUND=0"
for /f "tokens=1,2*" %%a in ('pnputil /enum-drivers 2^>nul') do (
    if /i "%%a"=="Published" if /i "%%b"=="Name:" (
        set "OEM_INF=%%c"
    )
    if /i "%%a"=="Original" if /i "%%b"=="Name:" (
        set "ORIG_INF=%%c"
        for %%n in (!INF_NAMES!) do (
            if /i "!ORIG_INF!"=="%%n" (
                echo ------------------
                echo Removing driver: %%n ^(!OEM_INF!^)
                pnputil /delete-driver "!OEM_INF!" /uninstall /force
                if !ERRORLEVEL! EQU 0 (
                    echo Successfully removed: %%n
                ) else (
                    echo Failed to remove: %%n ^(Error code !ERRORLEVEL!^)
                )
                set /a FOUND+=1
                echo.
            )
        )
    )
)

if !FOUND! EQU 0 (
    echo No matching Qualcomm USB Userspace drivers found in the driver store.
) else (
    echo.
    echo Removed !FOUND! driver package^(s^).
)

echo.
pause
endlocal