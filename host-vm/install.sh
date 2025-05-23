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
    NET1_NET="-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE_HELPER"
    NET1_DEV="-device virtio-net-pci,netdev=net1,mac=$MAC2,addr=5"
    NET2_NET="-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE_HELPER"
    NET2_DEV="-device virtio-net-pci,netdev=net2,mac=$MAC3,addr=6"
    cat << EOF >> .build/install.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \
-uuid $HOST_SYS_UUID \
-cdrom $ISO_FILE \
-device nvme,drive=NVME2,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN2 \
-drive file=$BOOT_DISK,if=none,id=NVME2 \
-device virtio-rng -boot menu=on,splash-time=2000 \
-drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
-drive if=pflash,format=raw,file=vm_vars.fd \
$NET0_NET \
$NET0_DEV \
$NET1_NET \
$NET1_DEV \
$NET2_NET \
$NET2_DEV
EOF
	echo "creating .build/start_attempt.sh"
	cat << EOF >> .build/start_attempt.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \
-uuid $HOST_SYS_UUID \
-debugcon file:bootlog -global isa-debugcon.iobase=0x402 \
-device virtio-rng -boot menu=on,splash-time=2000 \
-drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
-drive if=pflash,format=raw,file=vm_vars.fd \
-drive file=efidisk,format=raw,if=none,id=NVME1 -device nvme,drive=NVME1,serial=$SN3 \
$NET0_NET \
$NET0_DEV \
$NET1_NET \
$NET1_DEV \
$NET2_NET \
$NET2_DEV
EOF

	echo "creating .build/start_remote.sh"
	cat << EOF >> .build/start_remote.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \
-uuid $HOST_SYS_UUID \
-debugcon file:bootlog -global isa-debugcon.iobase=0x402 \
-device virtio-rng -boot menu=on,splash-time=2000 \
-drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
-drive if=pflash,format=raw,file=vm_vars.fd \
$NET0_NET \
$NET0_DEV \
$NET1_NET \
$NET1_DEV \
$NET2_NET \
$NET2_DEV
EOF
	echo "creating .build/start_local.sh"
	cat << EOF >> .build/start_local.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \
-uuid $HOST_SYS_UUID \
-device nvme,drive=NVME2,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN2 \
-drive file=$BOOT_DISK,if=none,id=NVME2 \
-device virtio-rng -boot menu=on,splash-time=2000 \
-drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
$NET0_NET \
$NET0_DEV \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE_HELPER \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE_HELPER \
-device virtio-net-pci,netdev=net2,mac=$MAC3
EOF
}

rm -f .start
rm -rf .build

check_install_args $# "$1" "$2" "$3"

check_host_depends

if [ $# -gt 3 ] && [ "$4" == "-n" ] || [ "$4" == "-f" ]; then
    echo "Reusing current disk"
else
    pushd ../target-vm
    create_host_disk
    popd
fi

BOOT_DISK=$(find ../target-vm/ -name nvme2.qcow2 -print)
if [ -z "$BOOT_DISK" ]; then
    echo " ../target-vm/disks/nvme2.qcow2 not found!"
    exit 1
else
    BOOT_DISK=$(realpath $BOOT_DISK)
    echo "using $BOOT_DISK"
fi

rm -rf efi
rm -f efi.tgz

cp -fv $DIR/../ISO/OVMF_VARS.fd vm_vars.fd

create_install_startup

chmod 755 .build/install.sh
chmod 755 .build/start_local.sh
chmod 755 .build/start_remote.sh
chmod 755 .build/start_attempt.sh

check_qargs

if [ $# -gt 3 ] && [ "$4" == "-f" ]; then
    echo "Skipping install. Run \"./start.sh local\" and then \"./netsetup.sh\" to configure the network."
    echo ""
    exit 0
fi

echo ""
echo " Be sure to create the root account with ssh access."
echo " Reboot to complete the install and login to the root account."
echo ""
echo " Record the host interface name and ip address with \"ip -br address show\" command."
echo ""
echo " Next step will be to run the \"./netsetup.sh\" script."
echo ""

bash .build/install.sh &
