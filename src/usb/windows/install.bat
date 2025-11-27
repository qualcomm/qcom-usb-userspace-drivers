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

:: Loop through all .inf files in the folder
for %%f in ("%CURRENT_DIR%\*.inf") do (
	echo ------------------
    echo Installing driver: %%~nxf
    pnputil /add-driver "%%f" /install

    if !ERRORLEVEL! EQU 0 (
        echo Successfully installed: %%~nxf
    ) else (
        echo Failed to install: %%~nxf (Error code !ERRORLEVEL!)
    )
    echo.
)

pause
endlocal
