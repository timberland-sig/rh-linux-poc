#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

HOST=$(hostanme)
VMNAME1=centos-vm
VMNAME2=fedora-vm
MAC1="52:54:88:12:02:57"
MAC2="52:57:88:12:02:02"
MAC3="52:57:88:12:03:03"

create_disks() {
	if [ ! -d $1 ]; then
		mkdir $1 
	fi

	echo "creating disks"
	rm -f $1/boot.qcow2
	qemu-img create -f qcow2 $1/boot.qcow2 70G
}

copy_disks() {
	if [ ! -d $1 ]; then
	    echo " error: $1 not found"
		exit 1
	fi

	if [ ! -d $2 ]; then
		mkdir $2 
	fi

	echo "copy boot disk"
	cp $1/boot.qcow2 $2/nvme1.qcow2
}

install_qemu1() {
qemu-system-x86_64 -name $1 --enable-kvm -bios OVMF-pure-efi.fd \
-cpu host -m 4G -smp 4 -vnc :0 -cdrom $2 \
-device nvme,drive=NVME1,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=054db6da9793b3c4c901 \
-drive file=$1/boot.qcow2,if=none,id=NVME1 -netdev bridge,br=br0,id=net0,helper=/usr/libexec/qemu-bridge-helper \
-device virtio-net-pci,netdev=net0,mac=$3
}

create_disks $VMNAME1
create_disks $VMNAME2

echo ""
echo " Connect to console with vncviewer $HOST:0 "
echo " and complete installation."
echo ""
echo " Script will continue when installation is done."
echo ""

install_qemu1 $VMNAME1 $HOME/ISO/CentOS-Stream-9-latest-x86_64-dvd1.iso $MAC1

copy_disks $VMNAME1 $VMNAME2

