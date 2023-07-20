#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh

HOST=`hostname`
VMNAME=`basename $PWD`

START_ACTION="nbft|local"

display_start_help() {
  echo " Usage: ./start.sh <$START_ACTION> "
  echo " "
  echo " Starts the QEMU VM named $VMNAME"
  echo ""
  echo "    local   - boot $VMNAME without the host-vm disk"
  echo "    nbft    - boot $VMNAME with host-vm disk - the host-vm must be shutdown"
  echo ""
  echo "   E.g.:"
  echo "          $0 local"
  echo "          $0 nbft"
  echo " "
}

if [ $# -lt 1 ] ; then
        display_start_help
        exit 1
fi

if [ ! -d .build ]; then
	echo "Error: $PWD/.build not found!"
	exit 1
fi

if [ ! -d disks ]; then
	echo "Error: $PWD/disks not found!"
	exit 1
fi

if [ ! -f disks/boot.qcow2 ]; then
	echo "Error: $PWD/disks/boot.qcow2 not found!"
	exit 1
fi

if [ ! -f disks/nvme1.qcow2 ]; then
	echo "Error: $PWD/disks/nvme1.qcow2 not found!"
	exit 1
fi

check_qargs

case "$1" in
    nbft)
		if [ ! -f disks/nvme2.qcow2 ]; then
			echo "Error: $PWD/disks/nvme2.qcow2 not found!"
			exit 1
		fi
        check_netport
        bash .build/start_nbft.sh &
    ;;
    local)
        check_netport
        bash .build/start_local.sh &
    ;;
    *)
    echo " Error: $1 not valid"
    display_start_help
    exit 1
    ;;
esac

echo ""
echo " Log into the root account and run \"./start-nvme-target.sh\" to start the NVMe/TCP soft target."

