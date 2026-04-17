// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause

// Qualcomm USB Userspace Driver Installer
// Self-extracting EXE: a ZIP payload containing INF+CAT files is appended
// at build time. At runtime the payload is extracted to a temp directory,
// drivers are installed via pnputil, and the temp directory is cleaned up.
// Must be run as Administrator.
//
// Usage:
//   qcom-usb-userspace-drivers.exe                 Install (auto-upgrades old version)
//   qcom-usb-userspace-drivers.exe /uninstall      Uninstall all previously installed drivers
//   qcom-usb-userspace-drivers.exe /query          Query installed version
//   qcom-usb-userspace-drivers.exe /force          Force install (skip version check)
//   qcom-usb-userspace-drivers.exe /version        Print installer version and exit
//   qcom-usb-userspace-drivers.exe /help           Print usage

#include <windows.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <shlwapi.h>
#include <shellapi.h>

#include "miniz.h"
#include "version.h"

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")

// ============================================================================
// Conflicting driver packages — removed before fresh or upgrade installs
// ============================================================================

// Kernel-mode driver INFs (from qcom-usb-kernel-drivers)
static const char *kKernelDriverINFs[] = {
    "qcfilter.inf",
    "qcwwan.inf",
    "qdbusb.inf",
    "qcwdfmdm.inf",
    "qcwdfser.inf",
    "qcmdm.inf",
    "qcser.inf",
    "qcnet.inf"
};
#define NUM_KERNEL_DRIVER_INFS (sizeof(kKernelDriverINFs) / sizeof(kKernelDriverINFs[0]))

// Legacy QPM-managed package names (installed via Qualcomm Package Manager)
static const char *kLegacyQpmPackages[] = {
    "qud",
    "qud.internal",
    "qud.slt",
    "Qualcomm_Userspace_Driver",
};
#define NUM_LEGACY_QPM_PACKAGES (sizeof(kLegacyQpmPackages) / sizeof(kLegacyQpmPackages[0]))

// ============================================================================
// Payload trailer — appended after the ZIP at the end of the EXE
// ============================================================================

#pragma pack(push, 1)
typedef struct {
    char     magic[8];       // "QUSBPK01"
    uint64_t payloadOffset;  // Offset of ZIP data from start of file
    uint64_t payloadSize;    // Size of ZIP data in bytes
    uint32_t crc32;          // CRC32 of ZIP data
    uint32_t reserved;       // Reserved for future use
} PayloadTrailer;
#pragma pack(pop)

static const char kPayloadMagic[8] = { 'Q','U','S','B','P','K','0','1' };
#define TRAILER_SIZE sizeof(PayloadTrailer)

// ============================================================================
// Version comparison
// Parse version string "major.minor.patch.build" and compare.
// Returns: -1 if a < b, 0 if equal, 1 if a > b
// ============================================================================

typedef struct {
    int major, minor, patch, build;
} VersionInfo;

static bool ParseVersion(const char *str, VersionInfo *ver)
{
    memset(ver, 0, sizeof(*ver));
    if (!str || !*str) return false;
    int n = sscanf(str, "%d.%d.%d.%d",
                   &ver->major, &ver->minor, &ver->patch, &ver->build);
    return n >= 1;
}

static int CompareVersion(const VersionInfo *a, const VersionInfo *b)
{
    if (a->major != b->major) return a->major < b->major ? -1 : 1;
    if (a->minor != b->minor) return a->minor < b->minor ? -1 : 1;
    if (a->patch != b->patch) return a->patch < b->patch ? -1 : 1;
    if (a->build != b->build) return a->build < b->build ? -1 : 1;
    return 0;
}

// ============================================================================
// Registry helpers — track installed version
// ============================================================================

static bool RegReadString(HKEY hRoot, const char *subKey, const char *valueName,
                          char *buf, DWORD bufSize)
{
    HKEY hKey;
    if (RegOpenKeyExA(hRoot, subKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS)
        return false;

    DWORD type = 0, size = bufSize;
    LSTATUS status = RegQueryValueExA(hKey, valueName, NULL, &type,
                                      (LPBYTE)buf, &size);
    RegCloseKey(hKey);
    return status == ERROR_SUCCESS && type == REG_SZ;
}

static bool RegWriteString(HKEY hRoot, const char *subKey, const char *valueName,
                           const char *value)
{
    HKEY hKey;
    DWORD disposition;
    if (RegCreateKeyExA(hRoot, subKey, 0, NULL, REG_OPTION_NON_VOLATILE,
                        KEY_WRITE, NULL, &hKey, &disposition) != ERROR_SUCCESS)
        return false;

    LSTATUS status = RegSetValueExA(hKey, valueName, 0, REG_SZ,
                                    (const BYTE *)value,
                                    (DWORD)(strlen(value) + 1));
    RegCloseKey(hKey);
    return status == ERROR_SUCCESS;
}

static bool GetInstalledVersion(char *buf, DWORD bufSize)
{
    return RegReadString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                         INSTALLER_REG_VERSION, buf, bufSize);
}

static bool GetInstalledINFList(char *buf, DWORD bufSize)
{
    return RegReadString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                         INSTALLER_REG_INF_LIST, buf, bufSize);
}

static bool GetInstalledPackageName(char *buf, DWORD bufSize)
{
    return RegReadString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                         INSTALLER_REG_PACKAGE, buf, bufSize);
}

static bool GetInstallDate(char *buf, DWORD bufSize)
{
    return RegReadString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                         INSTALLER_REG_INSTALL_DATE, buf, bufSize);
}

static bool RegDeleteKey_Full(HKEY hRoot, const char *subKey)
{
    LSTATUS status = RegDeleteKeyA(hRoot, subKey);
    return status == ERROR_SUCCESS;
}

static void SaveInstallInfo(const char *version, const char *infList)
{
    RegWriteString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                   INSTALLER_REG_VERSION, version);
    RegWriteString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                   INSTALLER_REG_PACKAGE, INSTALLER_PACKAGE_NAME);
    RegWriteString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                   INSTALLER_REG_INF_LIST, infList);

    // Save install date
    SYSTEMTIME st;
    char dateBuf[64];
    GetLocalTime(&st);
    snprintf(dateBuf, sizeof(dateBuf), "%04d-%02d-%02d %02d:%02d:%02d",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    RegWriteString(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY,
                   INSTALLER_REG_INSTALL_DATE, dateBuf);
}

// ============================================================================
// Admin check / elevation
// ============================================================================

static bool IsRunningAsAdmin(void)
{
    BOOL isAdmin = FALSE;
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
    PSID adminGroup = NULL;

    if (AllocateAndInitializeSid(&ntAuthority, 2,
            SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS,
            0, 0, 0, 0, 0, 0, &adminGroup)) {
        CheckTokenMembership(NULL, adminGroup, &isAdmin);
        FreeSid(adminGroup);
    }
    return isAdmin != FALSE;
}

static bool RelaunchAsAdmin(int argc, char *argv[])
{
    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, MAX_PATH);

    // Rebuild argument string (skip argv[0])
    char args[2048] = {0};
    for (int i = 1; i < argc; i++) {
        if (i > 1) strcat_s(args, sizeof(args), " ");
        strcat_s(args, sizeof(args), argv[i]);
    }

    SHELLEXECUTEINFOA sei = {0};
    sei.cbSize = sizeof(sei);
    sei.lpVerb = "runas";
    sei.lpFile = exePath;
    sei.lpParameters = args[0] ? args : NULL;
    sei.nShow = SW_SHOWNORMAL;
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;

    if (!ShellExecuteExA(&sei))
        return false;

    if (sei.hProcess) {
        WaitForSingleObject(sei.hProcess, INFINITE);
        CloseHandle(sei.hProcess);
    }
    return true;
}

// ============================================================================
// Payload extraction
// ============================================================================

static bool ReadTrailer(const char *exePath, PayloadTrailer *trailer)
{
    HANDLE hFile = CreateFileA(exePath, GENERIC_READ, FILE_SHARE_READ,
                               NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE)
        return false;

    LARGE_INTEGER fileSize;
    if (!GetFileSizeEx(hFile, &fileSize) ||
        fileSize.QuadPart < (LONGLONG)TRAILER_SIZE) {
        CloseHandle(hFile);
        return false;
    }

    LARGE_INTEGER seekPos;
    seekPos.QuadPart = fileSize.QuadPart - (LONGLONG)TRAILER_SIZE;
    if (!SetFilePointerEx(hFile, seekPos, NULL, FILE_BEGIN)) {
        CloseHandle(hFile);
        return false;
    }

    DWORD bytesRead = 0;
    if (!ReadFile(hFile, trailer, (DWORD)TRAILER_SIZE, &bytesRead, NULL) ||
        bytesRead != TRAILER_SIZE) {
        CloseHandle(hFile);
        return false;
    }

    CloseHandle(hFile);
    return memcmp(trailer->magic, kPayloadMagic, 8) == 0;
}

static bool ExtractPayload(const char *exePath, const char *extractDir,
                           PayloadTrailer *trailer)
{
    HANDLE hFile = CreateFileA(exePath, GENERIC_READ, FILE_SHARE_READ,
                               NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE)
        return false;

    LARGE_INTEGER seekPos;
    seekPos.QuadPart = (LONGLONG)trailer->payloadOffset;
    if (!SetFilePointerEx(hFile, seekPos, NULL, FILE_BEGIN)) {
        CloseHandle(hFile);
        return false;
    }

    // Read ZIP data into memory
    size_t zipSize = (size_t)trailer->payloadSize;
    unsigned char *zipData = (unsigned char *)malloc(zipSize);
    if (!zipData) {
        CloseHandle(hFile);
        return false;
    }

    DWORD totalRead = 0;
    while (totalRead < (DWORD)zipSize) {
        DWORD toRead = (DWORD)min(zipSize - totalRead, 1024 * 1024);
        DWORD bytesRead = 0;
        if (!ReadFile(hFile, zipData + totalRead, toRead, &bytesRead, NULL) ||
            bytesRead == 0) {
            free(zipData);
            CloseHandle(hFile);
            return false;
        }
        totalRead += bytesRead;
    }
    CloseHandle(hFile);

    // Validate CRC
    uint32_t crc = (uint32_t)mz_crc32(MZ_CRC32_INIT, zipData, zipSize);
    if (crc != trailer->crc32) {
        printf("ERROR: Payload CRC mismatch (expected 0x%08X, got 0x%08X)\n",
               trailer->crc32, crc);
        free(zipData);
        return false;
    }

    // Extract using miniz
    mz_zip_archive zip = {0};
    if (!mz_zip_reader_init_mem(&zip, zipData, zipSize, 0)) {
        printf("ERROR: Failed to open embedded ZIP archive\n");
        free(zipData);
        return false;
    }

    mz_uint numFiles = mz_zip_reader_get_num_files(&zip);
    bool success = true;

    for (mz_uint i = 0; i < numFiles; i++) {
        mz_zip_archive_file_stat fileStat;
        if (!mz_zip_reader_file_stat(&zip, i, &fileStat)) {
            success = false;
            break;
        }

        char fullPath[MAX_PATH];
        snprintf(fullPath, MAX_PATH, "%s\\%s", extractDir, fileStat.m_filename);

        // Convert forward slashes
        for (char *p = fullPath; *p; p++) {
            if (*p == '/') *p = '\\';
        }

        if (mz_zip_reader_is_file_a_directory(&zip, i)) {
            CreateDirectoryA(fullPath, NULL);
        } else {
            // Ensure parent directory exists
            char parentDir[MAX_PATH];
            strncpy_s(parentDir, MAX_PATH, fullPath, _TRUNCATE);
            PathRemoveFileSpecA(parentDir);
            CreateDirectoryA(parentDir, NULL);

            // Extract to memory and write using Win32 API
            size_t uncompSize = 0;
            void *data = mz_zip_reader_extract_to_heap(&zip, i, &uncompSize, 0);
            if (data) {
                HANDLE hOut = CreateFileA(fullPath, GENERIC_WRITE, 0,
                    NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
                if (hOut != INVALID_HANDLE_VALUE) {
                    DWORD written = 0;
                    WriteFile(hOut, data, (DWORD)uncompSize, &written, NULL);
                    CloseHandle(hOut);
                } else {
                    printf("ERROR: Failed to write %s (error %lu)\n",
                           fileStat.m_filename, GetLastError());
                    success = false;
                }
                mz_free(data);
            } else {
                printf("ERROR: Failed to extract %s\n", fileStat.m_filename);
                success = false;
            }
        }

        if (!success) break;
    }

    mz_zip_reader_end(&zip);
    free(zipData);
    return success;
}

// ============================================================================
// Driver uninstall / install via pnputil
// ============================================================================

// Helper: delete a single OEM driver package via pnputil
static void DeleteOemDriver(const char *infName, const char *oemName)
{
    char cmdLine[512];
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    DWORD exitCode = 1;

    printf("  Removing driver: %s (OEM: %s)\n", infName, oemName);

    snprintf(cmdLine, sizeof(cmdLine),
             "pnputil /delete-driver %s /uninstall /force", oemName);

    si.cb = sizeof(si);
    if (!CreateProcessA(NULL, cmdLine, NULL, NULL, FALSE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        printf("  WARNING: Failed to launch pnputil for uninstall\n");
        return;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    if (exitCode == 0) {
        printf("  OK: %s (%s) uninstalled\n", infName, oemName);
    } else {
        printf("  WARNING: %s (%s) uninstall returned code %lu (may already be removed)\n",
               infName, oemName, exitCode);
    }
}

static int UninstallDriverByINF(const char *infName)
{
    // Use pnputil /enum-drivers to find ALL OEM names for this INF,
    // then /delete-driver to remove each one immediately as it is found.
    // A single INF may appear multiple times in the driver store if
    // several versions were installed, each under a different OEM name.
    char cmdLine[512];
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    char tempFile[MAX_PATH];
    char tempDir[MAX_PATH];

    // Write pnputil output to a temp file so we can parse it
    GetTempPathA(MAX_PATH, tempDir);
    snprintf(tempFile, MAX_PATH, "%spnputil_enum_%lu.txt",
             tempDir, GetCurrentProcessId());

    snprintf(cmdLine, sizeof(cmdLine),
             "cmd /c pnputil /enum-drivers > \"%s\" 2>&1", tempFile);

    si.cb = sizeof(si);
    if (!CreateProcessA(NULL, cmdLine, NULL, NULL, FALSE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    // Parse the output and uninstall each matching OEM driver immediately
    FILE *fp = fopen(tempFile, "r");
    if (!fp) {
        DeleteFileA(tempFile);
        return 1;
    }

    char line[512];
    char currentOem[128] = {0};

    while (fgets(line, sizeof(line), fp)) {
        // Look for "Published Name:" lines
        char *p = strstr(line, "Published Name");
        if (!p) p = strstr(line, "Published name");
        if (p) {
            char *colon = strchr(p, ':');
            if (colon) {
                colon++;
                while (*colon == ' ') colon++;
                // Trim newline
                char *nl = strchr(colon, '\n');
                if (nl) *nl = '\0';
                nl = strchr(colon, '\r');
                if (nl) *nl = '\0';
                strncpy_s(currentOem, sizeof(currentOem), colon, _TRUNCATE);
            }
        }

        // Look for "Original Name:" lines
        p = strstr(line, "Original Name");
        if (!p) p = strstr(line, "Original name");
        if (p) {
            char *colon = strchr(p, ':');
            if (colon) {
                colon++;
                while (*colon == ' ') colon++;
                char *nl = strchr(colon, '\n');
                if (nl) *nl = '\0';
                nl = strchr(colon, '\r');
                if (nl) *nl = '\0';

                if (_stricmp(colon, infName) == 0 && currentOem[0]) {
                    DeleteOemDriver(infName, currentOem);
                    currentOem[0] = '\0';
                }
            }
        }
    }
    fclose(fp);
    DeleteFileA(tempFile);

    return 0;  // Non-fatal: proceed with install even if uninstall failed
}

static int InstallDriver(const char *infPath, const char *infName)
{
    char cmdLine[MAX_PATH + 64];
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    DWORD exitCode = 1;

    si.cb = sizeof(si);
    snprintf(cmdLine, sizeof(cmdLine),
             "pnputil /add-driver \"%s\" /install", infPath);

    printf("  Installing: %s\n", infName);

    if (!CreateProcessA(NULL, cmdLine, NULL, NULL, FALSE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        printf("  ERROR: Failed to launch pnputil (error %lu)\n", GetLastError());
        return 1;
    }

    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    if (exitCode == 0) {
        printf("  OK: %s installed successfully\n", infName);
    } else {
        printf("  FAILED: %s (pnputil exit code %lu)\n", infName, exitCode);
    }
    return (int)exitCode;
}

// ============================================================================
// Uninstall all previously installed INFs (from registry list)
// ============================================================================

static void UninstallOldDrivers(void)
{
    char infList[4096] = {0};
    if (!GetInstalledINFList(infList, sizeof(infList))) {
        printf("No previously installed driver list found.\n\n");
        return;
    }

    printf("Uninstalling previous userspace driver packages...\n");

    // INF list is semicolon-separated: "qcadb.inf;qcserlib.inf;..."
    char *ctx = NULL;
    char *token = strtok_s(infList, ";", &ctx);
    while (token) {
        // Trim whitespace
        while (*token == ' ') token++;
        if (*token) {
            UninstallDriverByINF(token);
        }
        token = strtok_s(NULL, ";", &ctx);
    }
    printf("\n");
}

// ============================================================================
// Uninstall conflicting kernel-mode driver packages (pnputil)
// ============================================================================

static void UninstallKernelDrivers(void)
{
    printf("Checking for conflicting kernel-mode driver packages...\n");

    for (size_t i = 0; i < NUM_KERNEL_DRIVER_INFS; i++) {
        // UninstallDriverByINF returns 0 on success or if not found
        UninstallDriverByINF(kKernelDriverINFs[i]);
    }
    printf("\n");
}

// ============================================================================
// Uninstall legacy QPM-managed packages (qpm-cli)
// ============================================================================

static bool IsQpmCliAvailable(void)
{
    // Try running "qpm-cli --version" silently to check if it exists
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    char cmdLine[256] = "cmd /c qpm-cli --version >nul 2>&1";

    si.cb = sizeof(si);
    if (!CreateProcessA(NULL, cmdLine, NULL, NULL, FALSE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        return false;
    }
    WaitForSingleObject(pi.hProcess, 5000);  // 5 second timeout
    DWORD exitCode = 1;
    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return exitCode == 0;
}

static int UninstallQpmPackage(const char *packageName)
{
    char cmdLine[512];
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    DWORD exitCode = 1;

    snprintf(cmdLine, sizeof(cmdLine),
             "cmd /c qpm-cli --uninstall %s 2>&1", packageName);

    si.cb = sizeof(si);
    if (!CreateProcessA(NULL, cmdLine, NULL, NULL, FALSE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        printf("  WARNING: Failed to launch qpm-cli for %s\n", packageName);
        return 1;
    }

    WaitForSingleObject(pi.hProcess, 60000);  // 60 second timeout
    GetExitCodeProcess(pi.hProcess, &exitCode);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    if (exitCode == 0) {
        printf("  OK: Legacy package '%s' uninstalled\n", packageName);
    } else {
        printf("  INFO: Legacy package '%s' not installed or already removed (exit %lu)\n",
               packageName, exitCode);
    }
    return 0;  // Non-fatal
}

static void UninstallLegacyQpmPackages(void)
{
    printf("Checking for legacy QPM-managed packages...\n");

    if (!IsQpmCliAvailable()) {
        printf("  qpm-cli not found on PATH — skipping legacy package check.\n\n");
        return;
    }

    printf("  qpm-cli found. Attempting to remove legacy packages...\n");
    for (size_t i = 0; i < NUM_LEGACY_QPM_PACKAGES; i++) {
        UninstallQpmPackage(kLegacyQpmPackages[i]);
    }
    printf("\n");
}

// ============================================================================
// Remove all conflicting packages before installation
// ============================================================================

static void UninstallConflictingPackages(void)
{
    printf("------------------------------------------\n");
    printf(" Removing conflicting driver packages\n");
    printf("------------------------------------------\n\n");

    // 1. Legacy QPM-managed packages (try first — may remove kernel+userspace)
    UninstallLegacyQpmPackages();

    // 2. Previous userspace installation (tracked in registry)
    UninstallOldDrivers();

    // 3. Kernel-mode driver packages (from qcom-usb-kernel-drivers)
    UninstallKernelDrivers();

    printf("------------------------------------------\n");
    printf(" Conflicting package removal complete\n");
    printf("------------------------------------------\n\n");
}

// ============================================================================
// Temp directory helpers
// ============================================================================

static bool CreateTempExtractDir(char *outPath, size_t outSize)
{
    char tempBase[MAX_PATH];
    DWORD len = GetTempPathA(MAX_PATH, tempBase);
    if (len == 0 || len >= MAX_PATH) return false;

    snprintf(outPath, outSize, "%sQcomUsbDrivers_%lu",
             tempBase, GetCurrentProcessId());
    return CreateDirectoryA(outPath, NULL) ||
           GetLastError() == ERROR_ALREADY_EXISTS;
}

static void DeleteDirectoryRecursive(const char *dir)
{
    WIN32_FIND_DATAA fd;
    char search[MAX_PATH];
    snprintf(search, MAX_PATH, "%s\\*", dir);
    HANDLE hFind = FindFirstFileA(search, &fd);
    if (hFind == INVALID_HANDLE_VALUE) return;

    do {
        if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0)
            continue;

        char fullPath[MAX_PATH];
        snprintf(fullPath, MAX_PATH, "%s\\%s", dir, fd.cFileName);

        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            DeleteDirectoryRecursive(fullPath);
        } else {
            DeleteFileA(fullPath);
        }
    } while (FindNextFileA(hFind, &fd));

    FindClose(hFind);
    RemoveDirectoryA(dir);
}

// ============================================================================
// Driver store query helpers (for /query)
// ============================================================================

typedef struct {
    char originalName[128];   // e.g. "qcwwan.inf"
    char publishedName[128];  // e.g. "oem42.inf"
    char driverVersion[128];  // e.g. "01/01/2024 1.0.0.0"
    char providerName[128];   // e.g. "Qualcomm"
    char className[128];      // e.g. "Net"
} DriverStoreEntry;

#define MAX_DRIVER_ENTRIES 64

// Parse pnputil /enum-drivers output and find entries matching any of the
// given INF names. Returns the number of matches found.
static int QueryDriverStore(const char *infNames[], size_t numNames,
                            DriverStoreEntry *results, int maxResults)
{
    char cmdLine[512];
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi = {0};
    char tempFile[MAX_PATH];
    char tempDir[MAX_PATH];
    int found = 0;

    GetTempPathA(MAX_PATH, tempDir);
    snprintf(tempFile, MAX_PATH, "%spnputil_query_%lu.txt",
             tempDir, GetCurrentProcessId());

    snprintf(cmdLine, sizeof(cmdLine),
             "cmd /c pnputil /enum-drivers > \"%s\" 2>&1", tempFile);

    si.cb = sizeof(si);
    if (!CreateProcessA(NULL, cmdLine, NULL, NULL, FALSE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        return 0;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    FILE *fp = fopen(tempFile, "r");
    if (!fp) {
        DeleteFileA(tempFile);
        return 0;
    }

    // Parse the output block by block.
    // Each driver entry has: Published Name, Original Name, Provider Name,
    // Class Name, Class GUID, Driver Version, Signer Name
    char line[512];
    char curPublished[128] = {0};
    char curOriginal[128] = {0};
    char curVersion[128] = {0};
    char curProvider[128] = {0};
    char curClass[128] = {0};

    while (fgets(line, sizeof(line), fp)) {
        // Helper: extract value after colon
        char *colon = strchr(line, ':');
        if (!colon) {
            // Blank line = end of entry block, check for match
            if (curOriginal[0] && found < maxResults) {
                for (size_t i = 0; i < numNames; i++) {
                    if (_stricmp(curOriginal, infNames[i]) == 0) {
                        strncpy_s(results[found].originalName, sizeof(results[found].originalName), curOriginal, _TRUNCATE);
                        strncpy_s(results[found].publishedName, sizeof(results[found].publishedName), curPublished, _TRUNCATE);
                        strncpy_s(results[found].driverVersion, sizeof(results[found].driverVersion), curVersion, _TRUNCATE);
                        strncpy_s(results[found].providerName, sizeof(results[found].providerName), curProvider, _TRUNCATE);
                        strncpy_s(results[found].className, sizeof(results[found].className), curClass, _TRUNCATE);
                        found++;
                        break;  // matched this entry to an INF name, move to next entry
                    }
                }
            }
            curPublished[0] = curOriginal[0] = curVersion[0] = curProvider[0] = curClass[0] = '\0';
            continue;
        }

        // Extract the value (skip colon + spaces, trim newline)
        char *val = colon + 1;
        while (*val == ' ') val++;
        char *nl = strchr(val, '\n');
        if (nl) *nl = '\0';
        nl = strchr(val, '\r');
        if (nl) *nl = '\0';

        if (strstr(line, "Published Name") || strstr(line, "Published name"))
            strncpy_s(curPublished, sizeof(curPublished), val, _TRUNCATE);
        else if (strstr(line, "Original Name") || strstr(line, "Original name"))
            strncpy_s(curOriginal, sizeof(curOriginal), val, _TRUNCATE);
        else if (strstr(line, "Driver Version") || strstr(line, "Driver version"))
            strncpy_s(curVersion, sizeof(curVersion), val, _TRUNCATE);
        else if (strstr(line, "Provider Name") || strstr(line, "Provider name"))
            strncpy_s(curProvider, sizeof(curProvider), val, _TRUNCATE);
        else if (strstr(line, "Class Name") || strstr(line, "Class name"))
            strncpy_s(curClass, sizeof(curClass), val, _TRUNCATE);
    }

    // Check last entry (file may not end with blank line)
    if (curOriginal[0] && found < maxResults) {
        for (size_t i = 0; i < numNames; i++) {
            if (_stricmp(curOriginal, infNames[i]) == 0) {
                strncpy_s(results[found].originalName, sizeof(results[found].originalName), curOriginal, _TRUNCATE);
                strncpy_s(results[found].publishedName, sizeof(results[found].publishedName), curPublished, _TRUNCATE);
                strncpy_s(results[found].driverVersion, sizeof(results[found].driverVersion), curVersion, _TRUNCATE);
                strncpy_s(results[found].providerName, sizeof(results[found].providerName), curProvider, _TRUNCATE);
                strncpy_s(results[found].className, sizeof(results[found].className), curClass, _TRUNCATE);
                found++;
                break;  // matched this entry to an INF name, move on
            }
        }
    }

    fclose(fp);
    DeleteFileA(tempFile);
    return found;
}

// Userspace driver INFs (the ones this installer manages)
static const char *kUserspaceDriverINFs[] = {
    "qcadb.inf",
    "qcfilter.inf",
    "qcmdmlib.inf",
    "qcserlib.inf",
    "qcwwanlib.inf",
    "qdblib.inf",
};
#define NUM_USERSPACE_DRIVER_INFS (sizeof(kUserspaceDriverINFs) / sizeof(kUserspaceDriverINFs[0]))

// ============================================================================
// Command handlers
// ============================================================================

static void PrintUsage(void)
{
    printf("Usage: qcom-usb-userspace-drivers [options]\n\n");
    printf("Options:\n");
    printf("  (no options)   Install drivers (auto-upgrades if older version found)\n");
    printf("  /uninstall     Uninstall all previously installed drivers\n");
    printf("  /query         Query installed driver packages and detect conflicts\n");
    printf("  /force         Force install (bypass version check, reinstall/downgrade)\n");
    printf("  /version       Print installer version and exit\n");
    printf("  /help          Print this help message\n");
}

static int CmdQuery(void)
{
    char version[128] = {0};
    char packageName[256] = {0};
    char infList[4096] = {0};
    char installDate[128] = {0};

    bool hasVersion = GetInstalledVersion(version, sizeof(version));
    bool hasPackage = GetInstalledPackageName(packageName, sizeof(packageName));
    bool hasInfList = GetInstalledINFList(infList, sizeof(infList));
    bool hasDate    = GetInstallDate(installDate, sizeof(installDate));

    // --- Section 1: Current userspace installation (from registry) ---
    printf("==========================================\n");
    printf(" Installed Userspace Driver Package\n");
    printf("==========================================\n");
    if (hasVersion) {
        printf("  Package:   %s\n", hasPackage ? packageName : "(unknown)");
        printf("  Version:   %s\n", version);
        if (hasDate)
            printf("  Installed: %s\n", installDate);
        if (hasInfList) {
            printf("  INF files: ");
            for (const char *p = infList; *p; p++) {
                if (*p == ';')
                    printf(", ");
                else
                    putchar(*p);
            }
            printf("\n");
        }
        printf("  Registry:  HKLM\\%s\n", INSTALLER_REG_KEY);
    } else {
        printf("  (not installed)\n");
    }

    // --- Section 2: Userspace drivers in driver store ---
    printf("\n==========================================\n");
    printf(" Userspace Drivers in Driver Store\n");
    printf("==========================================\n");
    DriverStoreEntry usEntries[MAX_DRIVER_ENTRIES];
    int usCount = QueryDriverStore(kUserspaceDriverINFs, NUM_USERSPACE_DRIVER_INFS,
                                   usEntries, MAX_DRIVER_ENTRIES);
    if (usCount > 0) {
        for (int i = 0; i < usCount; i++) {
            printf("  %-20s  OEM: %-14s  Version: %s\n",
                   usEntries[i].originalName,
                   usEntries[i].publishedName,
                   usEntries[i].driverVersion);
        }
    } else {
        printf("  (none found)\n");
    }

    // --- Section 3: Kernel-mode drivers in driver store ---
    printf("\n==========================================\n");
    printf(" Kernel-Mode Drivers in Driver Store\n");
    printf("==========================================\n");
    DriverStoreEntry kmEntries[MAX_DRIVER_ENTRIES];
    int kmCount = QueryDriverStore(kKernelDriverINFs, NUM_KERNEL_DRIVER_INFS,
                                   kmEntries, MAX_DRIVER_ENTRIES);
    if (kmCount > 0) {
        for (int i = 0; i < kmCount; i++) {
            printf("  %-20s  OEM: %-14s  Version: %s\n",
                   kmEntries[i].originalName,
                   kmEntries[i].publishedName,
                   kmEntries[i].driverVersion);
        }
        printf("\n  ** Kernel-mode drivers conflict with userspace drivers.\n");
        printf("     Run the installer to remove them automatically.\n");
    } else {
        printf("  (none found)\n");
    }

    // --- Section 4: Legacy QPM packages ---
    printf("\n==========================================\n");
    printf(" Legacy QPM-Managed Packages\n");
    printf("==========================================\n");
    if (IsQpmCliAvailable()) {
        printf("  qpm-cli found on PATH.\n");
        printf("  Known legacy packages: QUD, QUD.internal, Qualcomm_Userspace_Driver\n");
        printf("  Run the installer to attempt removal automatically.\n");
    } else {
        printf("  qpm-cli not found on PATH (no legacy packages detected).\n");
    }
    printf("\n");

    return 0;
}

static int CmdVersion(void)
{
    printf("%s Installer v%s\n", INSTALLER_PACKAGE_NAME, INSTALLER_VERSION_STR);
    return 0;
}

// ============================================================================
// Uninstall command
// ============================================================================

static int CmdUninstall(void)
{
    char version[128] = {0};
    char infList[4096] = {0};
    int removed = 0, total = 0;

    printf("==========================================\n");
    printf(" %s\n", INSTALLER_PACKAGE_NAME);
    printf(" Uninstaller v%s\n", INSTALLER_VERSION_STR);
    printf("==========================================\n\n");

    bool hasVersion = GetInstalledVersion(version, sizeof(version));
    bool hasInfList = GetInstalledINFList(infList, sizeof(infList));

    if (!hasVersion && !hasInfList) {
        printf("No installation found. Nothing to uninstall.\n");
        printf("\nPress any key to exit...\n");
        getchar();
        return 0;
    }

    if (hasVersion)
        printf("Installed version: %s\n\n", version);

    // Uninstall each driver from the INF list
    if (hasInfList && infList[0]) {
        printf("Removing installed drivers...\n\n");

        // Make a copy since strtok_s modifies the string
        char infListCopy[4096];
        strncpy_s(infListCopy, sizeof(infListCopy), infList, _TRUNCATE);

        char *ctx = NULL;
        char *token = strtok_s(infListCopy, ";", &ctx);
        while (token) {
            while (*token == ' ') token++;
            if (*token) {
                total++;
                printf("------------------\n");
                if (UninstallDriverByINF(token) == 0) {
                    removed++;
                }
                printf("\n");
            }
            token = strtok_s(NULL, ";", &ctx);
        }
    } else {
        printf("No INF list found in registry. Attempting to remove known drivers...\n\n");

        // Fall back to removing known userspace INFs
        for (size_t i = 0; i < NUM_USERSPACE_DRIVER_INFS; i++) {
            total++;
            printf("------------------\n");
            if (UninstallDriverByINF(kUserspaceDriverINFs[i]) == 0) {
                removed++;
            }
            printf("\n");
        }
    }

    // Clean up registry
    printf("Cleaning up registry...\n");
    if (RegDeleteKey_Full(HKEY_LOCAL_MACHINE, INSTALLER_REG_KEY)) {
        printf("  Registry key removed: HKLM\\%s\n\n", INSTALLER_REG_KEY);
    } else {
        printf("  Registry key not found or already removed.\n\n");
    }

    printf("==========================================\n");
    printf(" Uninstall Summary\n");
    printf("==========================================\n");
    printf("  Drivers processed: %d\n", total);
    printf("  Drivers removed:   %d\n", removed);
    printf("==========================================\n");

    printf("\nPress any key to exit...\n");
    getchar();
    return 0;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char *argv[])
{
    char exePath[MAX_PATH];
    char extractDir[MAX_PATH];
    char searchPath[MAX_PATH];
    WIN32_FIND_DATAA findData;
    HANDLE hFind;
    int installed = 0, failed = 0, total = 0;
    bool forceInstall = false;
    bool queryMode = false;
    bool versionMode = false;
    bool uninstallMode = false;

    // Parse command-line arguments
    for (int i = 1; i < argc; i++) {
        if (_stricmp(argv[i], "/query") == 0 || _stricmp(argv[i], "-query") == 0) {
            queryMode = true;
        } else if (_stricmp(argv[i], "/force") == 0 || _stricmp(argv[i], "-force") == 0) {
            forceInstall = true;
        } else if (_stricmp(argv[i], "/version") == 0 || _stricmp(argv[i], "-version") == 0) {
            versionMode = true;
        } else if (_stricmp(argv[i], "/uninstall") == 0 || _stricmp(argv[i], "-uninstall") == 0) {
            uninstallMode = true;
        } else if (_stricmp(argv[i], "/help") == 0 || _stricmp(argv[i], "-help") == 0 ||
                   _stricmp(argv[i], "/?") == 0 || _stricmp(argv[i], "-h") == 0) {
            PrintUsage();
            return 0;
        } else {
            printf("Unknown option: %s\n\n", argv[i]);
            PrintUsage();
            return 1;
        }
    }

    // Handle /version (no admin required)
    if (versionMode)
        return CmdVersion();

    // Handle /query (no admin required)
    if (queryMode)
        return CmdQuery();

    // Handle /uninstall (requires admin — elevation handled below)
    if (uninstallMode) {
        if (!IsRunningAsAdmin()) {
            printf("Administrator privileges required. Requesting elevation...\n");
            if (RelaunchAsAdmin(argc, argv))
                return 0;
            printf("ERROR: Failed to obtain administrator privileges.\n");
            printf("Please right-click the installer and select 'Run as administrator'.\n");
            printf("\nPress any key to exit...\n");
            getchar();
            return 1;
        }
        return CmdUninstall();
    }

    // --- Installation flow ---
    printf("==========================================\n");
    printf(" %s\n", INSTALLER_PACKAGE_NAME);
    printf(" Installer v%s\n", INSTALLER_VERSION_STR);
    printf("==========================================\n\n");

    // Check for admin
    if (!IsRunningAsAdmin()) {
        printf("Administrator privileges required. Requesting elevation...\n");
        if (RelaunchAsAdmin(argc, argv))
            return 0;
        printf("ERROR: Failed to obtain administrator privileges.\n");
        printf("Please right-click the installer and select 'Run as administrator'.\n");
        printf("\nPress any key to exit...\n");
        getchar();
        return 1;
    }

    // Get path to this EXE
    GetModuleFileNameA(NULL, exePath, MAX_PATH);

    // Read payload trailer
    PayloadTrailer trailer;
    if (!ReadTrailer(exePath, &trailer)) {
        printf("ERROR: No embedded driver payload found.\n");
        printf("This installer must be packaged using package.bat first.\n");
        printf("\nPress any key to exit...\n");
        getchar();
        return 1;
    }

    printf("Payload found: %llu bytes at offset %llu\n\n",
           (unsigned long long)trailer.payloadSize,
           (unsigned long long)trailer.payloadOffset);

    // Version check
    char installedVer[128] = {0};
    if (GetInstalledVersion(installedVer, sizeof(installedVer))) {
        VersionInfo viInstalled, viNew;
        ParseVersion(installedVer, &viInstalled);
        ParseVersion(INSTALLER_VERSION_STR, &viNew);
        int cmp = CompareVersion(&viNew, &viInstalled);

        printf("Currently installed version: %s\n", installedVer);
        printf("Installer version:           %s\n\n", INSTALLER_VERSION_STR);

        if (cmp == 0 && !forceInstall) {
            printf("Same version is already installed.\n");
            printf("Use /force to reinstall.\n");
            printf("\nPress any key to exit...\n");
            getchar();
            return 0;
        } else if (cmp < 0 && !forceInstall) {
            printf("A newer version (%s) is already installed.\n", installedVer);
            printf("Use /force to downgrade to %s.\n", INSTALLER_VERSION_STR);
            printf("\nPress any key to exit...\n");
            getchar();
            return 0;
        }

        if (cmp > 0) {
            printf("Upgrading from %s to %s...\n\n", installedVer,
                   INSTALLER_VERSION_STR);
        } else if (cmp < 0) {
            printf("FORCE: Downgrading from %s to %s...\n\n", installedVer,
                   INSTALLER_VERSION_STR);
        } else {
            printf("FORCE: Reinstalling version %s...\n\n", INSTALLER_VERSION_STR);
        }

        // Uninstall old drivers and conflicting packages before installing new ones
        UninstallConflictingPackages();
    } else {
        printf("No previous installation found.\n\n");
        // Still check for conflicting kernel/legacy packages on fresh install
        UninstallConflictingPackages();
    }

    // Create temp extraction directory
    if (!CreateTempExtractDir(extractDir, sizeof(extractDir))) {
        printf("ERROR: Failed to create temp directory\n");
        printf("\nPress any key to exit...\n");
        getchar();
        return 1;
    }

    printf("Extracting to: %s\n\n", extractDir);

    // Extract embedded ZIP payload
    if (!ExtractPayload(exePath, extractDir, &trailer)) {
        printf("ERROR: Failed to extract driver payload\n");
        DeleteDirectoryRecursive(extractDir);
        printf("\nPress any key to exit...\n");
        getchar();
        return 1;
    }

    printf("Extraction complete. Installing drivers...\n\n");

    // Find and install all INF files in the extracted directory
    // Also build a list for registry
    char infListBuf[4096] = {0};
    size_t infListLen = 0;

    snprintf(searchPath, MAX_PATH, "%s\\*.inf", extractDir);
    hFind = FindFirstFileA(searchPath, &findData);
    if (hFind == INVALID_HANDLE_VALUE) {
        printf("ERROR: No .inf files found in extracted payload\n");
        DeleteDirectoryRecursive(extractDir);
        printf("\nPress any key to exit...\n");
        getchar();
        return 1;
    }

    do {
        char infPath[MAX_PATH];
        total++;
        printf("------------------\n");
        snprintf(infPath, MAX_PATH, "%s\\%s", extractDir, findData.cFileName);

        if (InstallDriver(infPath, findData.cFileName) == 0) {
            installed++;
        } else {
            failed++;
        }

        // Append to INF list (semicolon-separated)
        if (infListLen > 0 && infListLen < sizeof(infListBuf) - 1) {
            infListBuf[infListLen++] = ';';
        }
        size_t nameLen = strlen(findData.cFileName);
        if (infListLen + nameLen < sizeof(infListBuf)) {
            memcpy(infListBuf + infListLen, findData.cFileName, nameLen);
            infListLen += nameLen;
            infListBuf[infListLen] = '\0';
        }

        printf("\n");
    } while (FindNextFileA(hFind, &findData));

    FindClose(hFind);

    // Save installed version and INF list to registry
    if (installed > 0) {
        SaveInstallInfo(INSTALLER_VERSION_STR, infListBuf);
        printf("Version %s recorded in registry.\n\n", INSTALLER_VERSION_STR);
    }

    // Cleanup temp directory
    printf("Cleaning up temporary files...\n\n");
    DeleteDirectoryRecursive(extractDir);

    printf("==========================================\n");
    printf(" Installation Summary\n");
    printf("==========================================\n");
    printf("  Version:   %s\n", INSTALLER_VERSION_STR);
    printf("  Total:     %d\n", total);
    printf("  Installed: %d\n", installed);
    printf("  Failed:    %d\n", failed);
    printf("==========================================\n");

    printf("\nPress any key to exit...\n");
    getchar();
    return failed > 0 ? 1 : 0;
}