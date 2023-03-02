#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../vm_lib.sh

HOST=`hostname`
VMNAME=`basename $PWD`
MAC1=0
MAC2=0
MAC3=0
QEMU=none
BRIDGE=none
SN1=0
SN2=0
QARGS=""

create_install_startup() {
	rm -rf .build
	mkdir .build

	echo "creating .build/install.sh"

	cat << EOF >> .build/install.sh
#!/bin/bash
$QEMU -name $VMNAME --enable-kvm -bios $DIR/../OVMF/OVMF-pure-efi.fd -cpu host -m 4G -smp 4 $QARGS \
-cdrom $ISO_FILE \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 \
-drive file=disks/boot.qcow2,if=none,id=NVME1 \
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1
exit
EOF
	echo "creating .build/start.sh"
	cat << EOF >> .build/start.sh
#!/bin/bash
$QEMU -name $VMNAME --enable-kvm -bios $DIR/../OVMF/OVMF-pure-efi.fd -cpu host -m 4G -smp 4 -boot menu=on $QARGS \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 \
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

check_install_args $# $1 "$2"

ISO_FILE="$1"

create_mac_addresses

create_disks

create_install_startup

chmod 755 .build/install.sh
chmod 755 .build/start.sh

if [ ! -z "${QARGS}" ]; then
	echo "$QRGS" > .qargs
	echo ""
	echo "Connect with \"vncviewer $HOST :0\""
	echo ""
	echo "Reboot/Shutdown when done with Install"
	echo ""
fi

bash .build/install.sh
