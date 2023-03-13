#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh

HOST=`hostname`
VMNAME=`basename $PWD`

check_host_depends

if [ ! -d .build ]; then
	echo "Error: $PWD/.build not found!"
	exit 1
fi

if [ ! -f .build/start.sh ]; then
	echo "Error: .build/start.sh not found!"
	exit 1
fi

if [  -f .qargs ]; then
	QARGS="$(cat .qargs)"
	NUM=$(echo "$QARGS" | cut -d ':' -f 2)
    echo ""
    echo "Connect with \"vncviewer $HOST:$NUM\""
    echo ""
fi

echo ""
echo " Connect to the \"host-vm\" console and immediately Press the ESC button to enter the UEFI setup menu."
echo " - Change the device boot order so the EFI Internal Shell starts first. Exit to continue."
echo " - The UEFI Shell will execute the startup script, let the countdown expire."
echo " - Then Reset to reboot the VM. The UEFI will connect to the NVMe/TCP target and boot."
echo ""

bash .build/start.sh &
