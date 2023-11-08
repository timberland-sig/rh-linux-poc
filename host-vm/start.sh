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
  echo "    attempt - inialize vm_vars.fd and boot with efidisk to program the nbft - target-vm must be running"
  echo "    remote  - start without efidisk and boot directly from nvme/tcp - target-vm must be running"
  echo "    local   - inialize vm_vars.fd boot from remote disk locally - target-vm must be shutdown"
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
        echo ""
        echo " Connect to the \"host-vm\" console and immediately Press ESC to enter the UEFI setup menu."
        echo " - Select Boot Manager and run the EFI Internal Shell."
        echo " - The UEFI Shell will execute the \"startup.nsh\" script and program the NBFT."
        echo " - Press ESC to exit Boot Manager select Reset to reboot the VM."
        echo " - UEFI will automatically boot with NVMe/TCP."
        echo " - Shutdown the VM and restart with "$0 remote" to boot with NVMe/TCP."
        echo ""
        cp -fv $DIR/../ISO/OVMF_VARS.fd vm_vars.fd
        check_qemu_command
        bash .build/start_attempt.sh &
    ;;
    remote)
        echo ""
        echo " Connect to the \"host-vm\" console and immediately Press ESC to enter the UEFI setup menu."
        echo " - Select Reset to reboot the VM."
        echo " - UEFI will automatically boot with NVMe/TCP."
        echo ""
        check_qemu_command
        bash .build/start_remote.sh &
    ;;
    local)
        echo ""
        echo " Allow the VM to boot normally, using the default"
        echo " - UEFI will automatically boot from the local disk without NVMe/TCP."
        echo " - Complete your work updating or modifying the local disk and shutdown."
        echo " - Shutdown the host-vm before starting the target-vm."
        echo " - Start target-vm nvme/tcp target server with \"start_nvme_target.sh\"."
        echo " - Restart the host-vm with "$0 attempt" to program the NBFT and boot with NVMe/TCP."
        echo ""
#        cp -fv $DIR/../ISO/OVMF_VARS.fd vm_vars.fd
        check_qemu_command
        bash .build/start_local.sh &
    ;;
    *)
    echo " Error: $1 not valid"
    display_start_help
    exit 1
    ;;
esac

check_qargs
check_netport

