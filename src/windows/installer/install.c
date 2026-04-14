// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause

// Qualcomm USB Userspace Driver Installer
// Self-extracting EXE: a ZIP payload containing INF+CAT files is appended
// at build time. At runtime the payload is extracted to a temp directory,
// drivers are installed via pnputil, and the temp directory is cleaned up.
// Must be run as Administrator.

#include <windows.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <shlwapi.h>
#include <shellapi.h>

#include "miniz.h"

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")

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

static bool RelaunchAsAdmin(const char *exePath)
{
    SHELLEXECUTEINFOA sei = {0};
    sei.cbSize = sizeof(sei);
    sei.lpVerb = "runas";
    sei.lpFile = exePath;
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
// Driver installation via pnputil
// ============================================================================

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

    printf("==========================================\n");
    printf(" Qualcomm USB Userspace Driver Installer\n");
    printf("==========================================\n\n");

    // Check for admin
    if (!IsRunningAsAdmin()) {
        printf("Administrator privileges required. Requesting elevation...\n");
        GetModuleFileNameA(NULL, exePath, MAX_PATH);
        if (RelaunchAsAdmin(exePath))
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
        printf("This installer must be packaged using build.bat first.\n");
        printf("\nPress any key to exit...\n");
        getchar();
        return 1;
    }

    printf("Payload found: %llu bytes at offset %llu\n\n",
           (unsigned long long)trailer.payloadSize,
           (unsigned long long)trailer.payloadOffset);

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
        printf("\n");
    } while (FindNextFileA(hFind, &findData));

    FindClose(hFind);

    // Cleanup temp directory
    printf("Cleaning up temporary files...\n\n");
    DeleteDirectoryRecursive(extractDir);

    printf("==========================================\n");
    printf(" Installation Summary\n");
    printf("==========================================\n");
    printf("  Total:     %d\n", total);
    printf("  Installed: %d\n", installed);
    printf("  Failed:    %d\n", failed);
    printf("==========================================\n");

    printf("\nPress any key to exit...\n");
    getchar();
    return failed > 0 ? 1 : 0;
}