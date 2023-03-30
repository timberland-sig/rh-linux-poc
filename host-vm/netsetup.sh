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

create_update_efi() {
    cat << EOF >> .build/update_efi.sh
#!/bin/bash
dnf update -y libnvme nvme-cli
dnf update -y dracut
dnf update -y dracut-network

modprobe nvme_fabrics
modprobe nvme_tcp

dracut -f -v --add nvmf

rm -f efi.tgz
pushd /boot
tar cvzf ~/efi.tgz efi
popd

echo ""
echo " scp the efi.tgz file to the hypervisor host, "
echo " or use \"./copy_efi.sh\" to retrieve efi.tgz"
echo ""
scp -o StrictHostKeyChecking=no efi.tgz $TESTUSR@host-gw-br2:$HOSTEFIDIR/efi.tgz
echo ""
echo " Shutdown this VM and run the \"./create_efidisk.sh\" script on the hypervisor."
echo ""
EOF
}

add_host_netsetup() {
    cat << EOF >> .build/netsetup.sh
dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y git tar vim nvme-cli systemd-networkd jq dbus-daemon memstrack
dnf update -y dracut
dnf install -y dracut-network

echo "$HOSTID" > /etc/nvme/hostid

./update_efi.sh

echo ""
echo " Run the \"target-vm/install.sh\" script to create the target-vm."
echo ""
EOF
}

create_copy_efi() {
    rm -f copy_efi.sh
    cat << EOF >> copy_efi.sh
#!/bin/bash
rm -f efi.tgz

echo ""
echo "scp the efi.tgz from the host-vm at $1"

scp -o StrictHostKeyChecking=no root@$1:efi.tgz .

echo ""
echo "Shutdown the host-vm and run the \"./create_efidisk.sh\" script."
echo ""
EOF
}

create_discover_target() {
    rm -f discover_target.sh
    cat << EOF >> discover_target.sh
#!/bin/bash
sudo modprobe nvme_fabrics
sudo modprobe nvme_tcp
sudo nvme discover --hostnqn=$HOSTNQN --transport=tcp --traddr=$TARGET_IP2 --trsvcid=4420
EOF
}

check_netsetup_args $#

rm -f copy_efi.sh
rm -f discover_target.sh
rm -f .build/netsetup.sh
rm -f .build/update_efi.sh
rm -f .build/hosts.txt

create_netsetup "$1" "$2" "$3"

add_host_netsetup

create_update_efi

create_hosts_file "$3"

create_copy_efi "$3"

create_discover_target

chmod 755 copy_efi.sh
chmod 755 discover_target.sh
chmod 755 .build/netsetup.sh
chmod 755 .build/update_efi.sh
chmod 755 .build/hosts.txt

rm -rf efi efi.tgz

echo ""
echo " scp  .build/{netsetup.sh,update_efi.sh,hosts.txt} root@$3:"
echo ""
ssh-keygen -R $3
scp -o StrictHostKeyChecking=no .build/{netsetup.sh,update_efi.sh,hosts.txt} root@$3:

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
echo ""

