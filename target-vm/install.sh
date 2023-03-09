#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

HOST=`hostname`
VMNAME=`basename $PWD`
QARGS=""
ISO_FILE=""

create_install_startup() {
	rm -rf .build
	mkdir .build

	echo "creating .build/install.sh"

	cat << EOF >> .build/install.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host -m 4G -smp 4 $QARGS \
-cdrom $ISO_FILE \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 \
-drive file=disks/boot.qcow2,if=none,id=NVME1 \
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1
EOF
	echo "creating .build/start.sh"
	cat << EOF >> .build/start.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host -m 4G -smp 4 -boot menu=on $QARGS \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1,bootindex=1 \
-drive file=disks/boot.qcow2,if=none,id=NVME1 \
-device nvme,drive=NVME2,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN2 \
-drive file=disks/nvme2.qcow2,if=none,id=NVME2 \
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1 \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE \
-device virtio-net-pci,netdev=net2,mac=$MAC3
exit
EOF
}

rm -f .qargs

ISO_FILE=$(find ../ -name boot.iso -print)
if [ -z "$ISO_FILE" ]; then
    check_install_args $# $1 "$2"
    ISO_FILE="$1"
else
    ISO_FILE=$(realpath $ISO_FILE)
    echo "using $ISO_FILE"
    check_install_args $# $ISO_FILE "$2"
fi

create_mac_addresses

create_target_disk

create_install_startup

chmod 755 .build/install.sh
chmod 755 .build/start.sh

if [ ! -z "${QARGS}" ]; then
	echo "$QARGS" > .qargs
	NUM=$(echo "$QARGS" | cut -d ':' -f 2)
	echo ""
	echo "Connect with \"vncviewer $HOST:$NUM\""
fi

echo ""
echo " Be sure to create the root account with ssh access."
echo " Reboot to complete the install and login to the root account."
echo " Then \"shutdown -h now\" the VM."
echo ""
echo " Next step will be restart the VM with \"./start.sh\" script."
echo ""

bash .build/install.sh &
