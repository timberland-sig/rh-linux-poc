#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh
. $DIR/../global_vars.sh

VMNAME=`basename $PWD`

create_nvme_target_config() {
    rm -f .build/tcp.json
    cp tcp.json.in .build/tcp.json
}

add_target_netsetup() {
    cat << EOF >> .build/netsetup.sh

dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y git tar vim nvme-cli nvmetcli

echo "$TARGETNQN" > /etc/nvme/hostnqn
echo "$TARGETID" > /etc/nvme/hostid

modprobe nvme_fabrics
modprobe nvmet_tcp
nvmetcli restore tcp.json
dmesg | grep nvmet
service firewalld stop

EOF
}

check_netsetup_args $#

create_netsetup "$1" "$2" "$3"

add_target_netsetup

create_hosts_file "$3"

create_nvme_target_config

chmod 775 .build/netsetup.sh
chmod 775 .build/tcp.json
chmod 775 .build/hosts.txt

echo ""
echo " scp  .build/{netsetup.sh,hosts.txt,tcp.json} root@$3:"
echo ""
scp .build/{netsetup.sh,hosts.txt,tcp.json} root@$3:

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
echo ""

