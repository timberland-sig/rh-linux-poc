#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh
. $DIR/../global_vars.sh

VMNAME=`basename $PWD`
TESTUSR="$USER"
HOST-EFI-DIR="$PWD"

add_host_netsetup() {
    cat << EOF >> .build/netsetup.sh

dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y git tar vim nvme-cli
dnf update -y dracut
dnf update -y dracut-network

echo "$HOSTNQN" > /etc/nvme/hostnqn
echo "$HOSTID" > /etc/nvme/hostid

modprobe nvme_fabrics
modprobe nvme_tcp

dracut -f -v --add nvmf

pushd /boot
tar cvzf ~/efi.tgz efi
popd

scp efi.tgz $TESTUSR@$host-gw:$HOST-EFI-DIR/efi.tgz

EOF
}

check_netsetup_args $#

create_netsetup "$1" "$2" "$3"

add_host_netsetup

create_hosts_file "$3"

chmod 775 .build/netsetup.sh
chmod 775 .build/hosts.txt

echo ""
echo " scp  .build/{netsetup.sh,hosts.txt} root@$3:"
echo ""
scp .build/{netsetup.sh,hosts.txt} root@$3:

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
echo ""

