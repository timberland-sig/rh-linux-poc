#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh

HOST=`hostname`
VMNAME=`basename $PWD`

START_ACTION="attempt|remote|local"

display_start_help() {
  echo " Usage: ./start.sh <$START_ACTION> "
  echo " "
  echo " Starts the QEMU VM named $VMNAME"
  echo ""
  echo "    attempt - start with the efidisk and set the nbft attempt before nvme/tcp boot"
  echo "    remote  - start with/out the efidisk and use nvme/tcp boot"
  echo "    local - start with/out the efidisk and use the local disk created by install.sh to boot"
  echo ""
  echo "   E.g.:"
  echo "          $0 attempt"
  echo "          $0 remote"
  echo "          $0 local"
  echo " "
}

if [ $# -lt 1 ] ; then
        display_start_help
        exit 1
fi

check_host_depends

if [ ! -d .build ]; then
	echo "Error: $PWD/.build not found!"
	exit 1
fi

case "$1" in
    attempt)
        cp -fv $DIR/../ISO/OVMF_VARS.fd vm_vars.fd
        echo ""
        echo " Connect to the \"host-vm\" console and immediately Press the ESC button to enter the UEFI setup menu."
        echo " - Change the device boot order so the EFI Internal Shell starts first. Exit to continue."
        echo " - The UEFI Shell will execute the \"startup.nsh\" script, let the countdown expire."
        echo " - Then Reset to reboot the VM. The UEFI will connect to the NVMe/TCP target and boot."
        echo ""
        check_qemu_command
        bash .build/start_remote.sh &
    ;;
    remote)
        echo ""
        echo " Connect to the \"host-vm\" console and immediately Press the ESC button to stop the \"startup.nsh\" countdown"
        echo " - There is no need to run the \"startup.nsh\" EFI Shell script again."
        echo " - Enter exit at the Shell prompt to reach the UEFI setup menu"
        echo " - Enter Reset at the UEFI setup menu to boot the VM. The UEFI will connect to the NVMe/TCP target and boot."
        echo ""
        check_qemu_command
        bash .build/start_remote.sh &
    ;;
    local)
        cp -fv $DIR/../ISO/OVMF_VARS.fd vm_vars.fd
        check_qemu_command
        bash .build/start_local.sh &
    ;;
    *)
    echo " Error: $1 not valid"
    display_start_help
    exit 1
    ;;
esac
