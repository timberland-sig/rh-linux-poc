#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE=none
QARGS=""
ISO_FILE=""

create_install_startup() {
    rm -rf .build
    mkdir .build

    echo "creating .build/install.sh"
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
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1 \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE \
-device virtio-net-pci,netdev=net2,mac=$MAC3
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
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1 \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE \
-device virtio-net-pci,netdev=net2,mac=$MAC3
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
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1 \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE \
-device virtio-net-pci,netdev=net2,mac=$MAC3
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
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1 \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE \
-device virtio-net-pci,netdev=net2,mac=$MAC3
EOF
}

rm -f .qargs
rm -f .start

check_install_args $# "$1" "$2"

check_host_depends

pushd ../target-vm
create_host_disk
popd

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

create_mac_addresses

create_install_startup

chmod 755 .build/install.sh
chmod 755 .build/start_local.sh
chmod 755 .build/start_remote.sh
chmod 755 .build/start_attempt.sh

if [ ! -z "${QARGS}" ]; then
	echo "$QARGS" > .qargs
	NUM=$(echo "$QARGS" | cut -d ':' -f 2)
	echo ""
	echo "Connect with \"vncviewer $HOST:$NUM\""
fi

echo ""
echo " Be sure to create the root account with ssh access."
echo " Reboot to complete the install and login to the root account."
echo " Record the host interface name and ip address with \"ip -br address show\" command."
echo ""
echo " Next step will be to the \"./netsetup.sh\" script."
echo ""

bash .build/install.sh &
