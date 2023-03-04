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
ISO_FILE=""

create_install_startup() {
        rm -rf .build
        mkdir .build

	echo " creating .build/install.sh"
	cat << EOF >> .build/install.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \
-nographic -device virtio-rng -boot menu=on,splash-time=2000 \
-drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
-drive if=pflash,format=raw,file=vm_vars.fd \
-netdev bridge,br=br0,id=net0,helper=$BRIDGE \
-device virtio-net-pci,netdev=net0,mac=$MAC1 \
-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE \
-device virtio-net-pci,netdev=net1,mac=$MAC2 \
-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE \
-device virtio-net-pci,netdev=net2,mac=$MAC3 \
-drive format=raw,file=fat:rw:./efi
EOF
	echo " creating .build/start.sh"
	cat << EOF >> .build/start.sh
#!/bin/bash
$QEMU -name $VMNAME -M q35 -accel kvm -cpu host -m 4G -smp 4 $QARGS \
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

}

rm -f .qargs

check_host_install_args $# "$1"

create_mac_addresses

create_install_startup

chmod 755 .build/install.sh
chmod 755 .build/start.sh

if [ ! -z "${QARGS}" ]; then
	echo "$QRGS" > .qargs
	echo ""
	echo "Connect with \"vncviewer $HOST:1\""
fi

#echo ""
#echo " Be sure to create the root account with ssh access."
#echo " Reboot to complete the install and login to the root account."
#echo " Record the host interface name and ip address with \"ip -br address show\" command and shutdown."
#echo ""
#echo " Next step will be to start the vm with the \"./start.sh\" script."
#echo ""

exit
#bash .build/install.sh
