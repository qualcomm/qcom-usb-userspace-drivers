// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause

#define STRINGIFY(s) #s
#define QCSTR(str) STRINGIFY(str)
#define WSTRINGIFY(s) L#s
#define QCWSTR(str) WSTRINGIFY(str)

#define QCOM_USB_DRIVERS_PRODUCT_VERSION 1.0.2.3
#define QCOM_USB_DRIVERS_FILE_VERSION 1,0,2,2
#define QCOM_USB_DRIVERS_PRODUCT_VERSION_STRING QCSTR(QCOM_USB_DRIVERS_PRODUCT_VERSION)
#define QCOM_USB_DRIVERS_PRODUCT_VERSION_STRING_W QCWSTR(QCOM_USB_DRIVERS_PRODUCT_VERSION)

#define QCOM_USB_DRIVERS_COMPANY_NAME "Qualcomm Technologies, Inc."
#define QCOM_USB_DRIVERS_COMPANY_NAME_W L"Qualcomm Technologies, Inc."

#define QCOM_USB_DRIVERS_PRODUCT_NAME "Qualcomm USB Userspace Drivers"
#define QCOM_USB_DRIVERS_PRODUCT_NAME_W L"Qualcomm USB Userspace Drivers"

#define QCOM_USB_DRIVERS_COPYRIGHT "Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries."
#define QCOM_USB_DRIVERS_COPYRIGHT_W L"Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries."
