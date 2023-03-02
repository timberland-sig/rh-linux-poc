#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`
IP2=0
IP3=0
BR0=0

if [ $# -lt 3 -o $# -gt 3 ] ; then
	display_netsetup_help
	exit 1
fi

create_nvme_target_config() {
	cp tcp1.json .build/tcp1.json
}

add_target_netsetup() {
    cat << EOF >> .build/netsetup.sh

dnf install -y git tar vim nvmetcli

modprobe nvme_fabrics
modprobe nvmet_tcp
nvmetcli restore tcp1.json
dmesg | grep nvmet
service firewalld stop

EOF
}

create_netsetup "$1" "$2" "$3"
add_target_netsetup
chmod 775 .build/netsetup.sh

create_host_file
chmod 775 .build/host.txt

create_nvme_target_config
chmod 775 .build/tcp1.json

echo ""
echo "scp .build/netsetup.sh root@$3:netsetup.sh"
echo ""

scp .build/netsetup.sh root@$3:netsetup.sh

echo ""
echo "scp .build/host.txt root@$3:host.txt"
echo ""

scp .build/host.txt root@$3:host.txt

echo ""
echo "scp .build/tcp1.json root@$3:tcp1.json"
echo ""

#scp .build/tcp1.json root@$3:tcp1.json

