#Requires -Version 5.0

param(
    [string]$OutputTo
)

# ==============================================================================
# Configuration
# ==============================================================================

$Script:SourceRoot = ".."       # Windows driver source directory
$Script:OutputRoot = "target"   # Default output directory, use -OutputTo to override
$Script:DriversDir = "drivers"

# Version header and mappings
$Script:VersionHeaderFile = "$SourceRoot\qcversion.h"
$Script:InfVersionMap = @{
    "qcadb.inf"    = "QCOM_USB_DRIVERS_PRODUCT_VERSION"
    "qcfilter.inf" = "QCOM_USB_DRIVERS_PRODUCT_VERSION"
    "qcmdmlib.inf" = "QCOM_USB_DRIVERS_PRODUCT_VERSION"
    "qcserlib.inf" = "QCOM_USB_DRIVERS_PRODUCT_VERSION"
    "qcwwanlib.inf"= "QCOM_USB_DRIVERS_PRODUCT_VERSION"
    "qdblib.inf"   = "QCOM_USB_DRIVERS_PRODUCT_VERSION"
}

# Binary assets to copy (pre-compiled files, etc.), as-is to OutputRoot.
$Script:BinaryAssets = @(
    @{ Source = "filter";  Destination = $Script:DriversDir }
)

# Build platforms used to compute the inf2cat OS target list.
$Script:BuildPlatforms = @(
    @{ Platform = "i386";  OSList = "10_X86" }
    @{ Platform = "amd64"; OSList = "10_X64" }
    @{ Platform = "arm64"; OSList = "10_RS4_ARM64,10_RS5_ARM64,10_19H1_ARM64,10_VB_ARM64" }
)

# Inf2Cat OS targets (built dynamically from BuildPlatforms)
$Script:Inf2CatOSList = ($Script:BuildPlatforms | ForEach-Object { $_.OSList }) -join ","

# WDK tool paths (auto-detect at runtime)
$Script:WDKRoot    = $null
$Script:WDKVersion = $null
$Script:WDKTools = @{
    "inf2cat.exe"  = $null
    "stampinf.exe" = $null
}

# Resolves a path to an absolute path relative to the script directory.
function Resolve-ScriptPath {
    param([Parameter(Mandatory)][string]$Path)

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $PSScriptRoot $Path
    }
    return $Path
}

# ==============================================================================
# Functions - Dependency Validation
# ==============================================================================

# Locates WDK installation via registry or default path, picks the latest version.
function Find-WDK {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots"

    foreach ($key in @("KitsRoot10", "KitsRoot81")) {
        $val = (Get-ItemProperty -Path $regPath -Name $key -ErrorAction SilentlyContinue).$key
        if ($val -and (Test-Path $val)) {
            $Script:WDKRoot = $val
            Write-Host "[INFO] WDK root found in registry: $WDKRoot"
            break
        }
    }

    if (-not $WDKRoot) {
        Write-Host "[INFO] WDK not found in registry. Checking default install location..."
        $defaultPath = "C:\Program Files (x86)\Windows Kits\10"
        if (Test-Path $defaultPath) {
            $Script:WDKRoot = $defaultPath
            Write-Host "[INFO] WDK root found at default location: $WDKRoot"
        }
    }

    if (-not $WDKRoot) {
        Write-Host "[WARN] WDK installation not found." -ForegroundColor Yellow
        return $false
    }

    $binDir = Join-Path $WDKRoot "bin"
    if (-not (Test-Path $binDir)) {
        Write-Host "[WARN] WDK bin directory not found: $binDir" -ForegroundColor Yellow
        return $false
    }

    $versions = Get-ChildItem -Path $binDir -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [Version]$_.Name } -Descending
    if (-not $versions) {
        Write-Host "[WARN] No WDK versions found under: $binDir" -ForegroundColor Yellow
        return $false
    }

    $Script:WDKVersion = $versions[0].Name
    Write-Host "[INFO] Latest WDK version: $WDKVersion"
    return $true
}

# Locates a WDK tool by name. Checks PATH first, then falls back to WDKRoot.
function Find-WDKTool {
    param(
        [Parameter(Mandatory)][string]$ToolName
    )

    $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[INFO] Found $ToolName on PATH: $($cmd.Source)"
        return $cmd.Source
    }

    if (-not $WDKRoot) {
        Write-Host "[ERROR] $ToolName not on PATH and WDKRoot is not set." -ForegroundColor Red
        return $null
    }

    $toolPath = Join-Path $WDKRoot "bin\$WDKVersion\x86\$ToolName"
    if (Test-Path $toolPath) {
        Write-Host "[INFO] Found ${ToolName}: $toolPath"
        return $toolPath
    }

    Write-Host "[ERROR] $ToolName not found at: $toolPath" -ForegroundColor Red
    return $null
}

# ==============================================================================
# Functions - Post Processing
# ==============================================================================

# Copies INF files to the drivers output directory.
function Copy-DriverOutputs {
    Write-Host "========================================"
    Write-Host " Copying Driver Sources"
    Write-Host "========================================`n"

    $destinationDir = Join-Path $OutputRoot $Script:DriversDir

    if (-not (Test-Path $Script:SourceRoot)) {
        Write-Host "[ERROR] Source directory not found: $Script:SourceRoot" -ForegroundColor Red
        return $false
    }

    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null

    # Copy *.inf files
    $infFiles = Get-ChildItem -Path $Script:SourceRoot -File -Filter "*.inf"
    foreach ($inf in $infFiles) {
        Copy-Item -Path $inf.FullName -Destination $destinationDir -Force
        Write-Host "[COPY] $($inf.Name) -> $destinationDir"
    }

    Write-Host ""
    Write-Host "[OK] $($infFiles.Count) INF file(s) copied to: $destinationDir" -ForegroundColor Green
    return $true
}

# Copies pre-compiled binary assets listed in BinaryAssets..
function Copy-BinaryAssets {
    Write-Host "========================================"
    Write-Host " Copying Binary Assets"
    Write-Host "========================================`n"

    foreach ($asset in $Script:BinaryAssets) {
        $srcPath        = Join-Path $Script:SourceRoot $asset.Source
        $destinationDir = Join-Path $OutputRoot        $asset.Destination

        if (-not (Test-Path $srcPath)) {
            Write-Host "[WARN] Binary asset not found: $srcPath" -ForegroundColor Yellow
            continue
        }

        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        Copy-Item -Path $srcPath -Destination $destinationDir -Recurse -Force
        Write-Host "[COPY] $($asset.Source) -> $($asset.Destination)"
    }

    Write-Host ""
    Write-Host "[OK] Binary assets copied." -ForegroundColor Green
    return $true
}

# Parses qcversion.h and returns a hashtable of { versionMacro, versionString }.
function Read-VersionFile {
    $FilePath = $Script:VersionHeaderFile

    if (-not (Test-Path $FilePath)) {
        Write-Host "[ERROR] Version header not found: $FilePath" -ForegroundColor Red
        return $null
    }

    $versions = [ordered]@{}
    $lines = Get-Content -Path $FilePath
    foreach ($line in $lines) {
        if ($line -match '^\s*#define\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+)') {
            $versionMacro  = $Matches[1]
            $versionString = $Matches[2]
            $versions[$versionMacro] = $versionString
        }
    }

    Write-Host "[VERSION] Parsed $($versions.Count) version(s) from: $FilePath"
    foreach ($key in $versions.Keys) {
        Write-Host "[VERSION] $($key.PadRight(32)) = $($versions[$key])"
    }
    return $versions
}

# Runs stampinf.exe on all .inf files in OutputRoot using version info from qcversion.h.
function Run-StampInf {
    Write-Host "========================================"
    Write-Host " Stamping INF Versions (stampinf)"
    Write-Host "========================================`n"

    $versions = Read-VersionFile
    if (-not $versions) {
        Write-Host "[ERROR] Failed to read version file." -ForegroundColor Red
        return $false
    }

    $destinationDir = Join-Path $OutputRoot $Script:DriversDir
    $infFiles = Get-ChildItem -Path $destinationDir -File -Filter "*.inf"
    if (-not $infFiles) {
        Write-Host "[WARN] No .inf files found in: $destinationDir" -ForegroundColor Yellow
        return $true
    }

    foreach ($inf in $infFiles) {
        $versionMacro = $InfVersionMap[$inf.Name]
        if (-not $versionMacro) {
            Write-Host "[WARN] No version mapping for: $($inf.Name)" -ForegroundColor Yellow
            continue
        }

        $version = $versions[$versionMacro]
        if (-not $version) {
            Write-Host "[ERROR] '$versionMacro' not found in version header for: $($inf.Name)" -ForegroundColor Red
            return $false
        }

        Write-Host "[STAMPINF] $($inf.Name) -> v$version ($versionMacro)"
        & $WDKTools["stampinf.exe"] -f "$($inf.FullName)" -d * -v $version 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] stampinf failed for $($inf.Name) (exit code: $LASTEXITCODE)" -ForegroundColor Red
            return $false
        }
    }

    Write-Host ""
    Write-Host "[OK] All INF versions stamped successfully." -ForegroundColor Green
    return $true
}

# Runs inf2cat.exe on all .inf files in OutputRoot to generate .cat files.
function Run-Inf2Cat {
    Write-Host "========================================"
    Write-Host " Generating Catalog Files (inf2cat)"
    Write-Host " OS targets: $Inf2CatOSList"
    Write-Host "========================================`n"

    $destinationDir = Join-Path $OutputRoot $Script:DriversDir
    $infFiles = Get-ChildItem -Path $destinationDir -File -Filter "*.inf"
    if (-not $infFiles) {
        Write-Host "[WARN] No .inf files found in: $destinationDir" -ForegroundColor Yellow
        return $false
    }

    foreach ($inf in $infFiles) {
        Write-Host "[INF2CAT] Found: $($inf.Name)"
    }

    & $WDKTools["inf2cat.exe"] /driver:"$destinationDir" /os:$Inf2CatOSList /uselocaltime 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] inf2cat failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        return $false
    }

    Write-Host ""
    Write-Host "[OK] Catalog files generated successfully." -ForegroundColor Green
    return $true
}

# ==============================================================================
# Main - Entry point: copies sources, stamps INFs, generates catalogs.
# ==============================================================================

function Main {
    Write-Host "========================================"
    Write-Host " QCOM USB Userspace Drivers - Build Script"
    Write-Host "========================================`n"

    if ($OutputTo) {
        $Script:OutputRoot = $OutputTo
    }
    $Script:OutputRoot        = Resolve-ScriptPath $Script:OutputRoot
    $Script:SourceRoot        = Resolve-ScriptPath $Script:SourceRoot
    $Script:VersionHeaderFile = Resolve-ScriptPath $Script:VersionHeaderFile

    # --- Step 1: Locate WDK ---
    if (-not (Find-WDK)) {
        Write-Host "[ERROR] WDK could not be found." -ForegroundColor Red
        Write-Host "[ERROR] Please install the Windows Driver Kit (WDK)." -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] WDK $WDKVersion is available at: $WDKRoot" -ForegroundColor Green
    Write-Host ""

    # --- Step 2: Verify WDK tools ---
    foreach ($toolName in @($WDKTools.Keys)) {
        if (-not $WDKTools[$toolName]) {
            $Script:WDKTools[$toolName] = Find-WDKTool -ToolName $toolName
            if (-not $WDKTools[$toolName]) {
                Write-Host "[ERROR] $toolName is missing. WDK installation may be incomplete." -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "[INFO] Using user-specified $toolName"
        }
        Write-Host "[OK] $toolName is available at: $($WDKTools[$toolName])" -ForegroundColor Green
        Write-Host ""
    }

    # --- Step 3: Clean output directory ---
    $cleanDir = Join-Path $OutputRoot $DriversDir
    if (-not $OutputTo -and (Test-Path $cleanDir)) {
        Remove-Item -Path $cleanDir -Recurse -Force
        Write-Host "[INFO] Cleaned output directory: $cleanDir"
    }
    Write-Host ""

    # --- Step 4: Copy INFs to output ---
    if (-not (Copy-DriverOutputs)) {
        Write-Host "[ERROR] Copy step failed. Aborting." -ForegroundColor Red
        exit 1
    }
    Write-Host ""

    # --- Step 4b: Copy binary assets (pre-compiled .sys, .dll, etc.) ---
    if (-not (Copy-BinaryAssets)) {
        Write-Host "[ERROR] Binary asset copy step failed. Aborting." -ForegroundColor Red
        exit 1
    }
    Write-Host ""

    # --- Step 5: Stamp INF versions ---
    if (-not (Run-StampInf)) {
        Write-Host "[ERROR] Version stamping failed." -ForegroundColor Red
        exit 1
    }
    Write-Host ""

    # --- Step 6: Generate catalog files ---
    if (-not (Run-Inf2Cat)) {
        Write-Host "[ERROR] Catalog generation failed." -ForegroundColor Red
        exit 1
    }
    Write-Host ""

    Write-Host "[OK] All build tasks completed successfully." -ForegroundColor Green
    Write-Host "[INFO] Output Location: $(Join-Path $OutputRoot $DriversDir)"
    Write-Host ""
}

Main
