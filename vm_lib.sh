#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

# NOTE: caller must include global_vars.sh before including this file.

echo "DIR = $DIR"

check_qargs() {
    if [  -f .qargs ]; then
        QARGS="$(cat .qargs)"
        NUM=$(echo "$QARGS" | cut -d ':' -f 2)
        echo ""
        echo "Connect to console with \"vncviewer $HOST:$NUM\""
    fi
}

check_qemu_command() {
    echo -n "using "
    if ! command -v qemu-system-x86_64 ; then
        echo " qemu-system-x86_64 is not installed"
        exit 1
    fi

    QEMU="$(command -v qemu-system-x86_64)"
    if [[ $QEMU =~ "/usr/local" ]]; then
            BRIDGE_HELPER="/usr/local/libexec/qemu-bridge-helper"
    else
            BRIDGE_HELPER="/usr/libexec/qemu-bridge-helper"
    fi
}

find_iso() {
    ISOVERSION="$(cat ../.diso)"
    ISO_FILE=$(find ../ -name $ISOVERSION -print)
    if [ -z "$ISO_FILE" ]; then
	echo " Error: $ISOVERSION not found"
	echo " run \"setup.sh -m iso\" or \"setup.sh prebuilt\""
	exit 1
    else
        ISO_FILE=$(realpath $ISO_FILE)
        echo "using $ISO_FILE"
    fi
}

display_netsetup_help2() {
  echo " "
  echo " Usage: netsetup.sh <ipaddr | localhost>"
  echo " "
  echo " Configures the network of $VMNAME"
  echo " "
  echo "  ipaddr - dhcp assigned ipv4 address of $VMNAME"
  echo "           - corresponds to br0 on the hypervisor host"
  echo ""
  echo "   Passing \"localhost\" in the ipaddr field is used with there is no br0 interface"
  echo "   configured on the hypervisor. See \"./install.sh\" help for more information."
  echo ""
  echo "   E.g.:"
  echo "          $0 192.168.0.63"
  echo "          $0 10.16.188.66"
  echo "          $0 localhost"
  echo " "
}

generate_serial_number() {
    hexdump -vn8 -e'4/4 "%08X" 1 "\n"' /dev/urandom
}
