#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`
TESTUSR="$USER"
HOSTEFIDIR="$PWD"

add_host_netsetup() {
    cat << EOF >> .build/netsetup.sh

dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y git tar vim nvme-cli
dnf update -y dracut
dnf install -y dracut-network

echo "$HOSTNQN" > /etc/nvme/hostnqn
echo "$HOSTID" > /etc/nvme/hostid

modprobe nvme_fabrics
modprobe nvme_tcp

dracut -f -v --add nvmf

pushd /boot
tar cvzf ~/efi.tgz efi
popd

echo ""
echo " scp the efi.tgz file to the hypervisor host"
scp -o StrictHostKeyChecking=no efi.tgz $TESTUSR@host-gw:$HOSTEFIDIR/efi.tgz

echo ""
echo " Please shutdown this VM and run the \"./create_efidisk.sh\" script."
#echo " Please shutdown this VM and run the \"target-vm/start.sh\" script."
echo ""

EOF
}

create_copy_efi() {
    rm -f efi.tgz

    cat << EOF >> copy_efi.sh
rm -f efi.tgz

echo ""
echo "scp the efi.tgz from the host-vm at $1"

scp -o StrictHostKeyChecking=no root@$1:efi.tgz .

echo ""
echo "Shutdown the host-vm and run the \"./create_efidisk.sh\" script."
echo ""
EOF
}

check_netsetup_args $#

create_netsetup "$1" "$2" "$3"

add_host_netsetup

create_hosts_file "$3"

create_copy_efi "$3"

chmod 775 copy_efi.sh
chmod 775 .build/netsetup.sh
chmod 775 .build/hosts.txt

rm -rf efi efi.tgz

echo ""
echo " scp  .build/{netsetup.sh,hosts.txt} root@$3:"
echo ""
scp -o StrictHostKeyChecking=no .build/{netsetup.sh,hosts.txt} root@$3:

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
echo ""

