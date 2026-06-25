@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"

REM Build drivers first as they are required by the installer
echo [INFO] Running build_drivers.bat...
call "%SCRIPT_DIR%build_drivers.bat"
if !ERRORLEVEL! neq 0 (
    echo [ERROR] build_drivers.bat failed. Aborting.
    exit /b !ERRORLEVEL!
)

for %%A in (x86 x64 arm64) do (
    REM Build tools for this architecture
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build_tools.ps1" -Platform %%A
    if !ERRORLEVEL! neq 0 exit /b !ERRORLEVEL!

    REM Build installer with arch-specific output name and architecture
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build-installer.ps1" -OutputName "qcom_usb_userspace_drivers_%%A.exe" -Arch %%A
    if !ERRORLEVEL! neq 0 exit /b !ERRORLEVEL!

    REM Sign the installer
    powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%sign.ps1" -InputFrom "%SCRIPT_DIR%target\qcom_usb_userspace_drivers_%%A.exe"
    if !ERRORLEVEL! neq 0 (
        echo [WARN] Signing failed for %%A. The unsigned exe is still available.
    )

    echo [DONE] %SCRIPT_DIR%target\qcom_usb_userspace_drivers_%%A.exe
)

endlocal
exit /b 0