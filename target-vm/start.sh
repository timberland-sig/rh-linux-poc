#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

HOST=`hostname`
VMNAME=`basename $PWD`

if [ ! -d disks ]; then
	echo "Error: $PWD/disks not found!"
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
    echo ""
    echo "Connect with \"vncviewer $HOST :0\""
    echo ""
fi

bash .build/start.sh &
