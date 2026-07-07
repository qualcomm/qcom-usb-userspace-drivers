param(
    [string]$OutputName = "installer.exe"
)

# ==============================================================================
# Configuration
# ==============================================================================

$Script:OutputRoot   = Join-Path $PSScriptRoot "target"
$Script:DriversDir   = "drivers"
$Script:ToolsDir     = "tools"
$Script:PayloadName  = "payload.zip"
$Script:VersionFile  = Join-Path $PSScriptRoot "..\qcversion.h"

# Files to promote from tools/ to the payload root (alongside drivers/ and tools/)
$Script:PromotedTools = @("qdclr.exe", "qdinstall.exe")

# ==============================================================================
# Functions
# ==============================================================================

# Assembles a payload zip from target/drivers and target/tools.
function New-Payload {
    Write-Host "========================================"
    Write-Host " Packaging Payload"
    Write-Host "========================================`n"

    $driversSource = Join-Path $Script:OutputRoot $Script:DriversDir
    $toolsSource   = Join-Path $Script:OutputRoot $Script:ToolsDir

    if (-not (Test-Path $driversSource)) {
        Write-Error "[ERROR] Drivers directory not found: $driversSource"
        exit 1
    }
    if (-not (Test-Path $toolsSource)) {
        Write-Error "[ERROR] Tools directory not found: $toolsSource"
        exit 1
    }

    # Create a temp staging directory
    $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    try {
        # Copy drivers/ and tools/ into the staging root
        Copy-Item -Path $driversSource -Destination $stagingDir -Recurse -Force
        Copy-Item -Path $toolsSource   -Destination $stagingDir -Recurse -Force
        Write-Host "[COPY] $Script:DriversDir, $Script:ToolsDir -> $stagingDir"

        # Promote specified tools to staging root and remove from tools/
        $destTools = Join-Path $stagingDir $Script:ToolsDir
        foreach ($toolFile in $Script:PromotedTools) {
            $srcFile = Join-Path $destTools $toolFile
            if (Test-Path $srcFile) {
                Copy-Item -Path $srcFile -Destination $stagingDir -Force
                Remove-Item -Path $srcFile -Force
                Write-Host "[PROMOTE] $toolFile -> payload root"
            } else {
                Write-Warning "[WARNING] Promoted tool not found in Tools: $toolFile"
            }
        }

        # Create the zip
        $payloadZip = Join-Path $Script:OutputRoot $Script:PayloadName
        if (Test-Path $payloadZip) {
            Remove-Item $payloadZip -Force
        }

        Write-Host "[ZIP] Creating: $payloadZip"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $payloadZip)

        Write-Host "[OK] Payload created: $payloadZip`n" -ForegroundColor Green
        return $payloadZip
    }
    finally {
        # Clean up staging directory
        if (Test-Path $stagingDir) {
            Remove-Item $stagingDir -Recurse -Force
        }
    }
}

# ==============================================================================
# Main Logic
# ==============================================================================

# --- Build payload ---
$PayloadFullPath = (Resolve-Path (New-Payload)).Path

# --- Parse version ---
$Version = "1.0.0.0"
if (Test-Path $Script:VersionFile) {
    $versionContent = Get-Content $Script:VersionFile -Raw
    if ($versionContent -match '#define\s+QCOM_USB_DRIVERS_PRODUCT_VERSION\s+([\d.]+)') {
        $Version = $Matches[1]
        Write-Host "[INFO] Version from header: $Version"
    } else {
        Write-Warning "QCOM_USB_DRIVERS_PRODUCT_VERSION not found in $($Script:VersionFile), using default: $Version"
    }
} else {
    Write-Warning "[WARNING] Version file not found: $($Script:VersionFile), using default: $Version"
}

# C# source code for the installer
$csharpSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("Qualcomm USB Userspace Driver Installer")]
[assembly: AssemblyDescription("Qualcomm USB Userspace Driver Installer")]
[assembly: AssemblyCompany("Qualcomm Technologies, Inc.")]
[assembly: AssemblyProduct("Qualcomm USB Userspace Drivers")]
[assembly: AssemblyCopyright("Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.")]
[assembly: AssemblyVersion("__VERSION__")]
[assembly: AssemblyFileVersion("__VERSION__")]
[assembly: AssemblyInformationalVersion("__VERSION__")]

namespace PayloadInstaller
{
    class Program
    {
        // Fixed install location.
        static readonly string InstallPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "Qualcomm", "Qualcomm USB Drivers");

        static readonly string QdinstallExe = Path.Combine(InstallPath, "qdinstall.exe");
        static readonly string LogFile      = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "Qualcomm", "QUD",
            "install_logs_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".txt");

        // Timeout in milliseconds to wait for qpm-cli / qsc-cli before giving up.
        const int LEGACY_TOOL_TIMEOUT_MS = 30000;

        static readonly string[] LegacyPackages = {
            "qualcomm_userspace_driver",
            "qud",
            "qud.slt",
            "qud.internal"
        };

        // ------------------------------------------------------------------ //
        // Logging helpers                                                      //
        // ------------------------------------------------------------------ //

        // StreamWriter kept open for the lifetime of the process.
        static StreamWriter _log = null;

        // Open (or create) the log file inside InstallPath.
        // Must be called after InstallPath has been created.
        static void OpenLog()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogFile));
                _log = new StreamWriter(LogFile, true, Encoding.UTF8);
                _log.AutoFlush = true;
                LogLine("==================================================================");
                LogLine("[LOG] Qualcomm USB Userspace Driver Installer  v__VERSION__");
                LogLine("[LOG] Session started : " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                LogLine("[LOG] Log file        : " + LogFile);
                LogLine("==================================================================");
            }
            catch (Exception ex)
            {
                // Log file is best-effort; never crash because of it.
                Console.Error.WriteLine("Warning: could not open log file '" + LogFile + "': " + ex.Message);
            }
        }

        static void CloseLog()
        {
            if (_log != null)
            {
                try { _log.Close(); } catch { }
                _log = null;
            }
        }

        // Write a line to the log file only (verbose / internal detail).
        static void LogLine(string message)
        {
            if (_log == null) return;
            try { _log.WriteLine("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + message); }
            catch { }
        }

        // Print to terminal AND write to log file.
        static void Print(string message)
        {
            Console.WriteLine(message);
            LogLine(message);
        }

        // Print to stderr AND write to log file.
        static void PrintError(string message)
        {
            Console.Error.WriteLine(message);
            LogLine("[ERROR] " + message);
        }

        // ------------------------------------------------------------------ //
        // Process execution                                                    //
        // ------------------------------------------------------------------ //

        // Run a command, capture its stdout+stderr, mirror them to the log,
        // and enforce a timeout so the installer never hangs indefinitely.
        // timeoutMs <= 0 means wait forever (use only for trusted internal tools).
        static int RunCommand(string fileName, string arguments, int timeoutMs = -1)
        {
            LogLine("[RUN] " + fileName + (arguments != null ? " " + arguments : ""));
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName               = fileName;
                if (arguments != null)
                    psi.Arguments          = arguments;
                psi.UseShellExecute        = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError  = true;
                psi.StandardOutputEncoding = Encoding.UTF8;
                psi.StandardErrorEncoding  = Encoding.UTF8;

                Process proc = Process.Start(psi);

                // Drain stdout and stderr asynchronously to prevent buffer deadlock.
                proc.OutputDataReceived += OnOutputData;
                proc.ErrorDataReceived  += OnErrorData;

                proc.BeginOutputReadLine();
                proc.BeginErrorReadLine();

                bool exited;
                if (timeoutMs > 0)
                    exited = proc.WaitForExit(timeoutMs);
                else
                {
                    proc.WaitForExit();
                    exited = true;
                }

                if (!exited)
                {
                    LogLine("[WARN] Process did not exit within " + timeoutMs + " ms  -  killing: " + fileName);
                    Console.Error.WriteLine("Warning: '" + fileName + "' timed out after "
                        + (timeoutMs / 1000) + " s and was terminated.");
                    try { proc.Kill(); } catch { }
                    proc.WaitForExit(5000);
                    return -1;
                }

                // Call WaitForExit() a second time (no-arg) to flush async streams.
                proc.WaitForExit();

                int code = proc.ExitCode;
                LogLine("[EXIT] " + fileName + " exited with code " + code);
                return code;
            }
            catch (Exception ex)
            {
                string msg = "Warning: Failed to run '" + fileName + "': " + ex.Message;
                Console.Error.WriteLine(msg);
                LogLine("[WARN] " + msg);
                return -1;
            }
        }

        // ------------------------------------------------------------------ //
        // Async output handlers (static methods - C# 5 compatible)             //
        // ------------------------------------------------------------------ //

        static void OnOutputData(object sender, DataReceivedEventArgs e)
        {
            if (e.Data != null)
                LogLine("[STDOUT] " + e.Data);
        }

        static void OnErrorData(object sender, DataReceivedEventArgs e)
        {
            if (e.Data != null)
                LogLine("[STDERR] " + e.Data);
        }

        // ------------------------------------------------------------------ //
        // Uninstall                                                            //
        // ------------------------------------------------------------------ //

                // Remove legacy qpm-cli / qsc-cli packages only.
        // Called as the first step of both Install() and Uninstall().
        static void RemoveLegacyPackages()
        {
            LogLine("[STEP] Starting legacy package cleanup");

            // Both qpm-cli and qsc-cli are fire-and-forget tools that must not
            // block the installer, so a hard timeout is enforced on each call.
            foreach (string pkg in LegacyPackages)
            {
                Print("\nUninstalling legacy product: " + pkg + "...");

                LogLine("[STEP] qpm-cli uninstall: " + pkg);
                int qpmRet = RunCommand("qpm-cli",
                    "--uninstall " + pkg + " --silent --force",
                    LEGACY_TOOL_TIMEOUT_MS);
                LogLine("[INFO] qpm-cli returned: " + qpmRet);

                LogLine("[STEP] qsc-cli uninstall: " + pkg);
                int qscRet = RunCommand("qsc-cli",
                    "tool uninstall -n " + pkg,
                    LEGACY_TOOL_TIMEOUT_MS);
                LogLine("[INFO] qsc-cli returned: " + qscRet);
            }
        }

        // Remove the currently installed driver (qdinstall -x) and wipe InstallPath.
        // Called as the second step of both Install() and Uninstall().
        static int RemoveCurrentInstallation()
        {
            int result = 0;
            if (File.Exists(QdinstallExe))
            {
                Print("\nRemoving current installation: " + QdinstallExe);
                LogLine("[STEP] Invoking qdinstall.exe -x");
                result = RunCommand(QdinstallExe, "-x");
                if (result != 0)
                    LogLine("[WARN] qdinstall.exe -x returned: " + result + " (continuing)");
            }
            else
            {
                LogLine("[INFO] qdinstall.exe not found at '" + QdinstallExe + "', skipping driver removal");
            }

            if (Directory.Exists(InstallPath))
            {
                LogLine("[STEP] Deleting install directory: " + InstallPath);
                try
                {
                    Directory.Delete(InstallPath, true);
                    LogLine("[INFO] Install directory deleted");
                }
                catch (IOException ex)
                {
                    string msg = "Warning: failed to delete " + InstallPath + ": " + ex.Message;
                    PrintError(msg);
                }
            }

            return result;
        }

        static int Uninstall()
        {
            // Step 1: remove legacy packages installed via qpm-cli / qsc-cli.
            RemoveLegacyPackages();

            // Step 2: uninstall the current driver and wipe the install directory.
            int result = RemoveCurrentInstallation();

            if (result == 0)
                Print("\nUninstall completed successfully.");
            else
                PrintError("\nUninstall failed with exit code: " + result);

            return result;
        }

        // ------------------------------------------------------------------ //
        // Install                                                              //
        // ------------------------------------------------------------------ //

        static int Install()
        {
            // Create InstallPath first so the log file can be opened inside it.
            Directory.CreateDirectory(InstallPath);
            OpenLog();

            LogLine("[STEP] Starting installation");
            LogLine("[INFO] Install path: " + InstallPath);

            // Step 1: remove legacy packages installed via qpm-cli / qsc-cli.
            Print("\nStep 1/4: Removing legacy installations...");
            RemoveLegacyPackages();

            // Step 2: uninstall the existing driver via qdinstall -x and wipe InstallPath.
            // This runs even when no legacy packages were found, ensuring a clean slate
            // before the fresh payload is extracted.
            Print("\nStep 2/4: Uninstalling current driver installation...");
            LogLine("[STEP] Running self-uninstall before fresh install");
            RemoveCurrentInstallation();
            Print("Uninstall step complete.");

            // Re-create the directory after RemoveCurrentInstallation() wiped it.
            Directory.CreateDirectory(InstallPath);

            try
            {
                // Step 3: extract the fresh payload.
                Print("\nStep 3/4: Extracting payload to: " + InstallPath);
                LogLine("[STEP] Extracting embedded payload");
                Assembly assembly = Assembly.GetExecutingAssembly();
                using (Stream resourceStream = assembly.GetManifestResourceStream("__PAYLOAD_NAME__"))
                {
                    if (resourceStream == null)
                    {
                        PrintError("Error: Embedded payload resource not found.");
                        return 1;
                    }
                    using (ZipArchive archive = new ZipArchive(resourceStream, ZipArchiveMode.Read))
                    {
                        archive.ExtractToDirectory(InstallPath);
                    }
                }
                Print("Extraction complete.");
                LogLine("[INFO] Payload extracted successfully");

                // Step 4: install the fresh driver.
                Print("\nStep 4/4: Installing driver...");
                LogLine("[STEP] Invoking qdinstall.exe -i");
                int result = RunCommand(QdinstallExe, "-i -p \"" + InstallPath + "\"");

                if (result == 0)
                {
                    Print("\nInstall completed successfully.");
                    LogLine("[INFO] Installation finished successfully");
                }
                else
                {
                    PrintError("\nInstall failed with exit code: " + result);
                    PrintError("Install files preserved at: " + InstallPath);
                    LogLine("[INFO] Installation failed  -  files preserved at: " + InstallPath);
                }
                return result;
            }
            catch (Exception ex)
            {
                PrintError("Error: " + ex.Message);
                LogLine("[EXCEPTION] " + ex.ToString());
                return 1;
            }
        }

        // ------------------------------------------------------------------ //
        // Entry point                                                          //
        // ------------------------------------------------------------------ //

        static int Main(string[] args)
        {
            // Parse arguments
            string mode = "install"; // default (no args)
            if (args.Length > 0)
            {
                string arg = args[0];
                if (arg == "-i" || arg == "--install" || arg == "/install")
                    mode = "install";
                else if (arg == "-u" || arg == "--uninstall" || arg == "/uninstall")
                    mode = "uninstall";
                else if (arg == "-v" || arg == "--version" || arg == "/version")
                    mode = "version";
                else
                {
                    Console.Error.WriteLine("Error: Invalid argument: " + arg);
                    Console.Error.WriteLine("Usage: QUD_Installer.exe [option]");
                    Console.Error.WriteLine("  -i, --install    Install drivers (default)");
                    Console.Error.WriteLine("  -u, --uninstall  Uninstall drivers");
                    Console.Error.WriteLine("  -v, --version    Show version");
                    return 1;
                }
            }

            if (mode == "version")
            {
                Console.WriteLine("Package version: __VERSION__");
                return 0;
            }

            int exitCode;
            if (mode == "uninstall")
            {
                // For a standalone uninstall the install directory already exists,
                // so we can open the log there before doing anything.
                if (Directory.Exists(InstallPath))
                    OpenLog();
                LogLine("[STEP] Mode: uninstall");
                exitCode = Uninstall();
            }
            else
            {
                LogLine("[STEP] Mode: install");
                exitCode = Install();
            }

            LogLine("[STEP] Session ended : " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  exit=" + exitCode);
            CloseLog();
            Console.WriteLine("\nPlease find the installation logs at: " + LogFile);
            return exitCode;
        }
    }
}
'@

# --- Resolve output exe path ---
# OutputName must be a bare file name. The exe is always written to OutputRoot.
if ($OutputName -match '[\\/]' -or [System.IO.Path]::IsPathRooted($OutputName)) {
    Write-Error "[ERROR] OutputName must be a bare file name: $OutputName"
    exit 1
}
$outputExe = Join-Path $Script:OutputRoot $OutputName

# Write C# source to a temp file in the system temp directory
$sourceFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.cs')
$csharpSource = $csharpSource.Replace("__VERSION__", $Version)
$csharpSource = $csharpSource.Replace("__PAYLOAD_NAME__", $Script:PayloadName)
Set-Content -Path $sourceFile -Value $csharpSource -Encoding UTF8

# Generate the application manifest (requireAdministrator).
$manifestSource = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
'@
$manifestFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.manifest')
Set-Content -Path $manifestFile -Value $manifestSource -Encoding UTF8

# Locate csc.exe: probe Framework64 first, then Framework, then PATH
$cscPath = $null
foreach ($ver in @("v4.0.30319")) {
    $candidate = "C:\Windows\Microsoft.NET\Framework64\$ver\csc.exe"
    if (Test-Path $candidate) { $cscPath = $candidate; break }
    $candidate = "C:\Windows\Microsoft.NET\Framework\$ver\csc.exe"
    if (Test-Path $candidate) { $cscPath = $candidate; break }
}
if (-not $cscPath) {
    $cscCmd = Get-Command "csc.exe" -ErrorAction SilentlyContinue
    if ($cscCmd) { $cscPath = $cscCmd.Source }
}
if (-not $cscPath) {
    Write-Error "[ERROR] csc.exe not found. Please install .NET Framework 4"
    exit 1
}

# Build the installer
Write-Host "Building installer..."
Write-Host "  Payload: $PayloadFullPath"
Write-Host "  Output:  $outputExe"

$cscArgs = @(
    "/target:exe",
    "/out:$outputExe",
    "/win32manifest:$manifestFile",
    "/resource:$PayloadFullPath,$($Script:PayloadName)",
    "/reference:System.IO.Compression.dll",
    "/reference:System.IO.Compression.FileSystem.dll",
    "/reference:System.dll",
    "/reference:System.Core.dll",
    $sourceFile
)

& $cscPath $cscArgs

$buildExitCode = $LASTEXITCODE
if (Test-Path $sourceFile)   { Remove-Item $sourceFile -Force }
if (Test-Path $manifestFile) { Remove-Item $manifestFile -Force }
if ($buildExitCode -eq 0)
{
    Write-Host "[OK] Build completed successfully: $outputExe" -ForegroundColor Green
    Write-Host ""
} else
{
    Write-Error "[ERROR] Build failed with exit code: $buildExitCode"
    exit $buildExitCode
}
