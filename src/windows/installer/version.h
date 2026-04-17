// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause

#ifndef QCOM_USB_INSTALLER_VERSION_H
#define QCOM_USB_INSTALLER_VERSION_H

#define INSTALLER_VERSION_MAJOR  1
#define INSTALLER_VERSION_MINOR  0
#define INSTALLER_VERSION_PATCH  1
#define INSTALLER_VERSION_BUILD  7

#define INSTALLER_VERSION_STR    "1.00.1.7"
#define INSTALLER_PACKAGE_NAME   "Qualcomm USB Userspace Drivers"
#define INSTALLER_PUBLISHER      "Qualcomm Technologies, Inc."
#define INSTALLER_INSTALL_DIR    "C:\\Program Files (x86)\\Qualcomm\\Qualcomm USB Userspace Drivers"
#define INSTALLER_EXE_NAME       "qcom-usb-userspace-drivers.exe"

// Registry key for tracking installed version
#define INSTALLER_REG_KEY        "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Qualcomm USB Userspace Drivers"
#define INSTALLER_REG_VERSION    "Version"
#define INSTALLER_REG_PACKAGE    "PackageName"
#define INSTALLER_REG_INF_LIST   "InstalledINFs"
#define INSTALLER_REG_INSTALL_DATE "InstallDate"

#endif // QCOM_USB_INSTALLER_VERSION_H