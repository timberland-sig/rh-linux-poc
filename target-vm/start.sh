#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

HOST=`hostname`
VMNAME=`basename $PWD`

if [ ! -d disks ]; then
	echo "Error: $PWD/disks not found!"
	exit 1
fi

if [ ! -f disks/nvme2.qcow2 ]; then
	echo "Error: $PWD/disks/nvme2.qcow2 not found!"
	exit 1
fi

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

if [ ! -f .start ]; then
    echo ""
    echo " Log into the root account and record the interface names for networks 2 and 3."
    echo " Use the \"ip -br address show\" command to display interface names"
    echo ""
    echo " Next step will be to run the \"./netsetup.sh\" script."
    echo ""
fi

touch .start

bash .build/start.sh &
