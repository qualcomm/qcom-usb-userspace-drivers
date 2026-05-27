@echo off
setlocal enabledelayedexpansion

:: ==============================================================================
:: qdinstall.bat - Qualcomm USB Kernel Driver Installer
::
:: Usage:
::   qdinstall.bat [-i] [<drivers_dir>] [-p <install_path>] [-v <version>]
::   qdinstall.bat -x
::
:: Options:
::   -i              Install drivers (default if no mode specified)
::   -x              Uninstall drivers
::   -p <path>       Installation path to register (optional; skips registry if omitted)
::   -v <version>    Version string for registry (optional; skips registry if omitted)
::   <drivers_dir>   Directory containing .inf files (default: script directory)
:: ==============================================================================

set "SCRIPT_DIR=%~dp0"
set "REG_KEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Qualcomm USB Drivers"
set "WWAN_SVC_NAME=qcmtusvc"

set "MODE=install"
set "DRIVERS_DIR="
set "INSTALL_PATH="
set "VERSION="

:: --------------------------------------------------------------------------
:: Parse arguments
:: --------------------------------------------------------------------------
:parse_args
if "%~1"=="" goto args_done

if /i "%~1"=="-i" (
    set "MODE=install"
    shift
    goto parse_args
)
if /i "%~1"=="-x" (
    set "MODE=uninstall"
    shift
    goto parse_args
)
if /i "%~1"=="-p" (
    if "%~2"=="" (
        echo ERROR: -p requires a path argument.
        exit /b 1
    )
    set "INSTALL_PATH=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="-v" (
    if "%~2"=="" (
        echo ERROR: -v requires a version argument.
        exit /b 1
    )
    set "VERSION=%~2"
    shift
    shift
    goto parse_args
)
:: Positional argument: drivers directory
if not defined DRIVERS_DIR (
    set "DRIVERS_DIR=%~1"
    shift
    goto parse_args
)

echo ERROR: Unknown argument: %~1
exit /b 1

:args_done

:: Default drivers directory to script directory
if not defined DRIVERS_DIR set "DRIVERS_DIR=%SCRIPT_DIR%"

:: --------------------------------------------------------------------------
:: Administrator check
:: --------------------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: This script must be run as Administrator.
    exit /b 1
)

:: --------------------------------------------------------------------------
:: Install
:: --------------------------------------------------------------------------
if /i "%MODE%"=="install" goto do_install
if /i "%MODE%"=="uninstall" goto do_uninstall

echo ERROR: Unknown mode: %MODE%
exit /b 1

:do_install
echo ========================================
echo  Installing Qualcomm USB Drivers
echo ========================================
echo.

:: Verify INF directory exists
if not exist "%DRIVERS_DIR%" (
    echo ERROR: Drivers directory not found: %DRIVERS_DIR%
    exit /b 1
)

:: Count INF files
set "INF_COUNT=0"
for %%f in ("%DRIVERS_DIR%*.inf") do set /a INF_COUNT+=1

if %INF_COUNT%==0 (
    echo ERROR: No .inf files found in: %DRIVERS_DIR%
    exit /b 1
)

echo [INFO] Found %INF_COUNT% INF file(s) in: %DRIVERS_DIR%
echo.

:: Install each INF
set "INSTALL_OK=1"
for %%f in ("%DRIVERS_DIR%*.inf") do (
    echo [PNPUTIL] Installing: %%~nxf
    pnputil /add-driver "%%f" /install
    set "RC=!errorlevel!"
    if !RC! neq 0 (
        if !RC! neq 3010 (
            echo ERROR: pnputil failed for %%~nxf ^(exit code: !RC!^)
            set "INSTALL_OK=0"
        ) else (
            echo [INFO] %%~nxf installed ^(reboot required^)
        )
    )
    echo.
)

if "%INSTALL_OK%"=="0" (
    echo ERROR: One or more drivers failed to install.
    exit /b 1
)

:: Trigger device scan
echo [INFO] Scanning for hardware changes...
pnputil /scan-devices
echo.

:: Register and start WWAN service (best effort)
if exist "%SCRIPT_DIR%tools\qcmtusvc.exe" (
    echo [INFO] Registering WWAN service...
    "%SCRIPT_DIR%tools\qcmtusvc.exe" install
    echo [INFO] Starting WWAN service...
    net start %WWAN_SVC_NAME%
)

:: Write registry only if both -p and -v were provided
if not defined INSTALL_PATH goto install_done
if not defined VERSION goto install_done

echo [INFO] Registering installation in Add/Remove Programs...
reg add "%REG_KEY%" /v "DisplayName"    /t REG_SZ    /d "Qualcomm USB Kernel Drivers"         /f >nul
reg add "%REG_KEY%" /v "DisplayVersion" /t REG_SZ    /d "%VERSION%"                           /f >nul
reg add "%REG_KEY%" /v "Publisher"      /t REG_SZ    /d "Qualcomm Technologies, Inc."         /f >nul
reg add "%REG_KEY%" /v "InstallLocation"/t REG_SZ    /d "%INSTALL_PATH%"                      /f >nul
reg add "%REG_KEY%" /v "UninstallString"/t REG_SZ    /d "\"%INSTALL_PATH%\qdinstall.bat\" -x" /f >nul
reg add "%REG_KEY%" /v "NoModify"       /t REG_DWORD /d 1                                     /f >nul
reg add "%REG_KEY%" /v "NoRepair"       /t REG_DWORD /d 1                                     /f >nul
echo [OK] Registration complete.
echo.

:install_done
echo [OK] Install completed successfully.
exit /b 0

:: --------------------------------------------------------------------------
:: Uninstall
:: --------------------------------------------------------------------------
:do_uninstall
echo ========================================
echo  Uninstalling Qualcomm USB Drivers
echo ========================================
echo.

:: Read InstallLocation from registry
set "INSTALL_LOCATION="
for /f "tokens=2*" %%a in ('reg query "%REG_KEY%" /v InstallLocation 2^>nul') do set "INSTALL_LOCATION=%%b"

:: Stop and unregister WWAN service before driver removal
if defined INSTALL_LOCATION (
    if exist "%INSTALL_LOCATION%\tools\qcmtusvc.exe" (
        echo [INFO] Stopping WWAN service...
        net stop %WWAN_SVC_NAME% 2>nul
        echo [INFO] Unregistering WWAN service...
        "%INSTALL_LOCATION%\tools\qcmtusvc.exe" uninstall
    )
)

:: Locate qdclr.exe: prefer install location, fall back to script directory
set "QDCLR_PATH="
if defined INSTALL_LOCATION (
    if exist "%INSTALL_LOCATION%\qdclr.exe" (
        set "QDCLR_PATH=%INSTALL_LOCATION%\qdclr.exe"
    )
)
if not defined QDCLR_PATH (
    if exist "%SCRIPT_DIR%qdclr.exe" (
        set "QDCLR_PATH=%SCRIPT_DIR%qdclr.exe"
    )
)
if not defined QDCLR_PATH (
    echo ERROR: qdclr.exe not found in install location or script directory.
    exit /b 1
)

echo [INFO] Running: %QDCLR_PATH%
"%QDCLR_PATH%"
set "QDCLR_RC=%errorlevel%"

if %QDCLR_RC% neq 0 (
    echo ERROR: qdclr.exe failed with exit code: %QDCLR_RC%
    exit /b %QDCLR_RC%
)

:: Trigger device scan
echo.
echo [INFO] Scanning for hardware changes...
pnputil /scan-devices
echo.

:: Remove registry entry
reg query "%REG_KEY%" >nul 2>&1
if %errorlevel%==0 (
    echo [INFO] Removing registry entry...
    reg delete "%REG_KEY%" /f >nul
    echo [OK] Registry entry removed.
)

echo.
echo [OK] Uninstall completed successfully.
exit /b 0