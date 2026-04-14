# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause

cmake_minimum_required(VERSION 3.10)
project(QcomUsbInstaller C)

add_executable(qcom_usb_installer
    install.c
    miniz.c
)

target_include_directories(qcom_usb_installer PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(qcom_usb_installer PRIVATE shlwapi shell32)

# Console subsystem so printf output is visible
set_target_properties(qcom_usb_installer PROPERTIES
    WIN32_EXECUTABLE FALSE
    OUTPUT_NAME "QcomUsbDriverInstaller"
)

# Request admin elevation via UAC
if(MSVC)
    target_link_options(qcom_usb_installer PRIVATE
        "/MANIFESTUAC:level='requireAdministrator' uiAccess='false'"
    )
endif()