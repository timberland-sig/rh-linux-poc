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
dnf remove -y nvme-cli libnvme
dnf copr disable -y $COPR_USER/$COPR_PROJECT
dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y nvme-cli libnvme
dnf update -y dracut
dnf update -y dracut-network

echo "$HOSTID" > /etc/nvme/hostid

modprobe nvme_fabrics
modprobe nvme_tcp
EOF
}

create_update_initramfs() {
    cat << EOF >> .build/update_initramfs.sh
#!/bin/bash
dracut -f -v --add nvmf
rm -f efi.tgz
pushd /boot
tar cvzf ~/efi.tgz efi
popd

echo ""
echo " Use \"./copy_efi.sh\" to retrieve efi.tgz, then"
echo " run the \"./create_efidisk.sh\" script on the hypervisor."
echo ""
echo " Shutdown the host-vm and start the target-vm."
echo ""
EOF
}

add_host_netsetup() {
    cat << EOF >> .build/netsetup.sh
dnf copr enable -y $COPR_USER/$COPR_PROJECT
dnf install -y git tar vim nvme-cli libnvme systemd-networkd jq dbus-daemon memstrack
dnf update -y dracut
dnf install -y dracut-network
echo "$HOSTID" > /etc/nvme/hostid

./update_initramfs.sh

echo ""
echo " Run the \"target-vm/install.sh\" script to create the target-vm."
echo ""
EOF
}

create_bridge_copy_efi() {
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

create_local_copy_efi() {
    cat << EOF >> copy_efi.sh
#!/bin/bash
rm -f efi.tgz
echo ""
echo "scp the efi.tgz from the host-vm at $1"
scp -o StrictHostKeyChecking=no -P 5555 root@localhost:efi.tgz .
echo ""
echo "Shutdown the host-vm and run the \"./create_efidisk.sh\" script."
echo ""
EOF
}

create_copy_efi() {
    rm -f copy_efi.sh
    case "$1" in
        localhost)
        create_local_copy_efi $1
        ;;
        *)
        create_bridge_copy_efi $1
        ;;
    esac
}

create_discover_target() {
    rm -f discover_target.sh
    cat << EOF >> discover_target.sh
#!/bin/bash
sudo modprobe nvme_fabrics
sudo modprobe nvme_tcp
sudo nvme discover --hostnqn=$HOSTNQN --transport=tcp --traddr=$TARGET_IP2 --trsvcid=4420
sudo nvme discover --hostnqn=$HOSTNQN --transport=tcp --traddr=$TARGET_IP3 --trsvcid=4420
EOF
}

check_netsetup_args $#

rm -f copy_efi.sh
rm -f discover_target.sh
rm -f .build/netsetup.sh
rm -f .build/update_efi.sh
rm -f .build/update_initramfs.sh
rm -f .build/hosts.txt

create_netsetup "$1" "$2" "$3"
add_host_netsetup
create_update_efi
create_update_initramfs
create_hosts_file "$3"
create_copy_efi "$3"
create_discover_target

chmod 755 copy_efi.sh
chmod 755 discover_target.sh
chmod 755 .build/netsetup.sh
chmod 755 .build/update_efi.sh
chmod 755 .build/update_initramfs.sh
chmod 755 .build/hosts.txt

rm -rf efi efi.tgz

check_netport

case "$3" in
    localhost)
        echo ""
        echo " scp -P 5555 .build/{netsetup.sh,update_initramfs.sh,update_efi.sh,hosts.txt} root@localhost:"
        echo ""
        ssh-keygen -R [localhost]:5555
        scp -o StrictHostKeyChecking=no -P 5555 .build/{netsetup.sh,update_initramfs.sh,update_efi.sh,hosts.txt} root@localhost:
        ;;
        *)
        echo ""
        echo " scp .build/{netsetup.sh,update_initramfs.sh,update_efi.sh,hosts.txt} root@$3:"
        echo ""
        ssh-keygen -R $3
        scp -o StrictHostKeyChecking=no .build/{netsetup.sh,update_initramfs.sh,update_efi.sh,hosts.txt} root@$3:
        ;;
   esac

echo ""
echo " Login to $VMNAME/root and run \"./netsetup.sh\" to complete the VM configuration"
echo ""

