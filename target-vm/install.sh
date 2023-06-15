#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE_HELPER=none
QARGS=""
ISO_FILE=""

create_install_startup() {
	rm -rf .build
	mkdir .build
	echo "creating .build/install.sh"
	cat << EOF >> .build/install.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host -m 4G -smp 4 $QARGS \
-uuid $TARGET_SYS_UUID \
-cdrom $ISO_FILE \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 \
-drive file=$BOOT_DISK,if=none,id=NVME1 \
$NET0_NET \
$NET0_DEV 
EOF
	echo "creating .build/start.sh"
	cat << EOF >> .build/start.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host -m 4G -smp 4 -boot menu=on $QARGS \
-uuid $TARGET_SYS_UUID \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1,bootindex=1 \
-drive file=$BOOT_DISK,if=none,id=NVME1 \
-device nvme,drive=NVME2,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN2 \
-drive file=disks/nvme2.qcow2,if=none,id=NVME2 \
$NET0_NET \
$NET0_DEV \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE_HELPER \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE_HELPER \
-device virtio-net-pci,netdev=net2,mac=$MAC3
exit
EOF
}

rm -f .start
rm -rf .build

check_install_args $# "$1" "$2" "$3"

if [ $# -gt 3 ] && [ "$4" == "-n" ] || [ "$4" == "-f" ]; then
    echo "Reusing current disk"
else
    create_target_disk
fi

BOOT_DISK=$(find . -name boot.qcow2 -print)
if [ -z "$BOOT_DISK" ]; then
    echo " $BOOT_DISK not found!"
    exit 1
else
    BOOT_DISK=$(realpath $BOOT_DISK)
    echo "using $BOOT_DISK"
fi

create_install_startup

chmod 755 .build/install.sh
chmod 755 .build/start.sh

check_qargs

if [ $# -gt 3 ] && [ "$4" == "-f" ]; then
    echo "Skipping install. Run \"./start.sh local\" and then \"./netsetup.sh\" to configure the network."
    echo ""
    exit 0
fi

echo ""
echo " Be sure to create the root account with ssh access."
echo " Reboot to complete the install and login to the root account."
echo " Then \"shutdown -h now\" the VM."
echo ""
echo " Next step will be restart the VM with \"./start.sh\" script."
echo ""

bash .build/install.sh &
