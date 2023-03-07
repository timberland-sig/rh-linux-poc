#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`

create_nvme_target_config() {
    rm -f .build/tcp.json
    cp tcp.json.in .build/tcp.json

    cat << EOF >> .build/tcp-target.sh
#!/bin/bash
modprobe nvme_fabrics
modprobe nvmet_tcp
nvmetcli restore tcp.json
dmesg | grep nvmet
service firewalld stop
EOF
}

add_target_netsetup() {
    cat << EOF >> .build/netsetup.sh

dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y git tar vim nvme-cli nvmetcli

echo "$TARGETNQN" > /etc/nvme/hostnqn
echo "$TARGETID" > /etc/nvme/hostid

echo ""
echo " Shutdown and run \"host-vm/install.sh\" to complete the host"
echo ""

EOF
}

add_target_netsetup() {
    cat << EOF >> .build/netsetup.sh

dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y git tar vim nvme-cli nvmetcli

echo "$TARGETNQN" > /etc/nvme/hostnqn
echo "$TARGETID" > /etc/nvme/hostid

EOF
}

check_netsetup_args $#

create_netsetup "$1" "$2" "$3"

add_target_netsetup

create_hosts_file "$3"

create_nvme_target_config

chmod 775 .build/netsetup.sh
chmod 775 .build/tcp-target.sh
chmod 775 .build/tcp.json
chmod 775 .build/hosts.txt

echo ""
echo " scp  .build/{netsetup.sh,tcp-target.sh,hosts.txt,tcp.json} root@$3:"
echo ""
scp .build/{netsetup.sh,hosts.txt,tcp-target.sh,tcp.json} root@$3:

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
echo ""

