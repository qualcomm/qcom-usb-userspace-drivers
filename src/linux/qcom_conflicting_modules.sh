#!/bin/bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause

set -e

MODULE_BLACKLIST_PATH=/lib/modules/$(uname -r)/kernel/drivers/usb/serial
QCOM_USBNET_AND_QMI_WWAN=/lib/modules/$(uname -r)/kernel/drivers/net/usb
CDC_WDM_PATH=/lib/modules/$(uname -r)/kernel/drivers/usb/class

MODULE_BLACKLIST_CONFIG=/etc/modprobe.d
BLACKLIST_FILE=$MODULE_BLACKLIST_CONFIG/blacklist.conf

QCOM_MODBIN_DIR=/sbin
QCOM_LN_RM_MK_DIR=/bin

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

usage() {
    echo "Usage: $0 <remove | restore>"
}

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: run as root or with sudo.${RESET}"
        exit 1
    fi
}

ensure_blacklist_file() {
    if [ ! -f "$BLACKLIST_FILE" ]; then
        touch "$BLACKLIST_FILE"
    fi
}

remove_flow() {
    echo -e "${GREEN}Removing conflicting modules...${RESET}"

    ensure_blacklist_file

    $QCOM_LN_RM_MK_DIR/chmod 777 "$BLACKLIST_FILE"

    # qcserial
    if grep -nr 'blacklist qcserial' "$BLACKLIST_FILE" >/dev/null 2>&1; then
        sed -i '/qcserial/d' "$BLACKLIST_FILE"
    fi

    echo "blacklist qcserial" >> "$BLACKLIST_FILE"
    echo "install qcserial /bin/false" >> "$BLACKLIST_FILE"
    echo "blacklisted qcserial module"

    if $QCOM_MODBIN_DIR/lsmod | grep -qw qcserial; then
        echo "qcserial is found. Unloading qcserial module"
        $QCOM_MODBIN_DIR/rmmod qcserial || true

        if $QCOM_MODBIN_DIR/lsmod | grep -qw qcserial; then
            echo -e "${RED}Failed to unload qcserial. Try manually: sudo rmmod qcserial${RESET}"
        fi
    fi

    if [ -f "$MODULE_BLACKLIST_PATH/qcserial.ko" ]; then
        echo "qcserial.ko is found. Renaming to qcserial_dup"
        mv "$MODULE_BLACKLIST_PATH/qcserial.ko" "$MODULE_BLACKLIST_PATH/qcserial_dup"
    fi

    # qmi_wwan
    if grep -nr 'blacklist qmi_wwan' "$BLACKLIST_FILE" >/dev/null 2>&1; then
        sed -i '/qmi_wwan/d' "$BLACKLIST_FILE"
    fi

    echo "blacklist qmi_wwan" >> "$BLACKLIST_FILE"
    echo "install qmi_wwan /bin/false" >> "$BLACKLIST_FILE"
    echo "blacklisted qmi_wwan module"

    if $QCOM_MODBIN_DIR/lsmod | grep -qw qmi_wwan; then
        echo "qmi_wwan is found. Unloading qmi_wwan module"
        $QCOM_MODBIN_DIR/rmmod qmi_wwan || true

        if $QCOM_MODBIN_DIR/lsmod | grep -qw qmi_wwan; then
            echo -e "${RED}Failed to unload qmi_wwan. Try manually: sudo rmmod qmi_wwan${RESET}"
        fi
    fi

    # cdc_wdm dependency
    if $QCOM_MODBIN_DIR/lsmod | grep -qw cdc_wdm; then
        echo "cdc_wdm is found. Unloading cdc_wdm module"
        $QCOM_MODBIN_DIR/rmmod cdc_wdm || true

        if $QCOM_MODBIN_DIR/lsmod | grep -qw cdc_wdm; then
            echo -e "${RED}Failed to unload cdc_wdm. Try manually: sudo rmmod cdc_wdm${RESET}"
        fi
    fi

    if [ -f "$CDC_WDM_PATH/cdc-wdm.ko" ]; then
        echo "cdc-wdm.ko is found. Renaming to cdc-wdm_dup"
        mv "$CDC_WDM_PATH/cdc-wdm.ko" "$CDC_WDM_PATH/cdc-wdm_dup"
    fi

    if [ -f "$QCOM_USBNET_AND_QMI_WWAN/qmi_wwan.ko" ]; then
        echo "qmi_wwan.ko is found. Renaming to qmi_wwan_dup"
        mv "$QCOM_USBNET_AND_QMI_WWAN/qmi_wwan.ko" "$QCOM_USBNET_AND_QMI_WWAN/qmi_wwan_dup"
    fi

    $QCOM_LN_RM_MK_DIR/chmod 644 "$BLACKLIST_FILE"

    depmod

    echo -e "${GREEN}Remove flow completed.${RESET}"
}

restore_flow() {
    echo -e "${GREEN}Restoring conflicting modules...${RESET}"

    ensure_blacklist_file

    $QCOM_LN_RM_MK_DIR/chmod 777 "$BLACKLIST_FILE"

    if grep -nr 'blacklist qcserial' "$BLACKLIST_FILE" >/dev/null 2>&1; then
        sed -i '/qcserial/d' "$BLACKLIST_FILE"
        echo "removed qcserial blacklist"
    fi

    if grep -nr 'blacklist qmi_wwan' "$BLACKLIST_FILE" >/dev/null 2>&1; then
        sed -i '/qmi_wwan/d' "$BLACKLIST_FILE"
        echo "removed qmi_wwan blacklist"
    fi

    $QCOM_LN_RM_MK_DIR/chmod 644 "$BLACKLIST_FILE"

    if ls "$MODULE_BLACKLIST_PATH"/qcserial_dup* >/dev/null 2>&1; then
        echo "qcserial_dup found. Restoring to qcserial.ko"
        mv "$MODULE_BLACKLIST_PATH"/qcserial_dup* "$MODULE_BLACKLIST_PATH/qcserial.ko"
    fi

    if ls "$CDC_WDM_PATH"/cdc-wdm_dup* >/dev/null 2>&1; then
        echo "cdc-wdm_dup found. Restoring to cdc-wdm.ko"
        mv "$CDC_WDM_PATH"/cdc-wdm_dup* "$CDC_WDM_PATH/cdc-wdm.ko"
    fi

    if ls "$QCOM_USBNET_AND_QMI_WWAN"/qmi_wwan_dup* >/dev/null 2>&1; then
        echo "qmi_wwan_dup found. Restoring to qmi_wwan.ko"
        mv "$QCOM_USBNET_AND_QMI_WWAN"/qmi_wwan_dup* "$QCOM_USBNET_AND_QMI_WWAN/qmi_wwan.ko"
    fi

    depmod

    echo -e "${GREEN}Restore flow completed.${RESET}"
}

ensure_root

case "$1" in
    remove)
        remove_flow
        ;;

    restore)
        restore_flow
        ;;

    *)
        usage
        exit 1
        ;;
esac

exit 0
