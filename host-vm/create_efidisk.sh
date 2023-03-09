#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

VMNAME=`basename $PWD`

if [ ! -f efi.tgz ]; then
	echo " error efi.tgz file missing"
	exit 1
fi

if [ ! -f eficonfig/NvmeOfCli.efi ]; then
	echo " error eficonfig/NvmeOfCli.efi file missing"
	exit 1
fi

sudo losetup -D loop1
sudo losetup -P loop1 $PWD/efidisk
sudo mkfs.vfat /dev/loop1p1
sudo losetup -D loop1

mkdir -p efi
sudo mount -t vfat -o loop,offset=1048576 $PWD/efidisk $PWD/efi
df efi
sudo tar xzvf efi.tgz
sudo cp -v $PWD/eficonfig/* $PWD/efi/EFI/BOOT
sudo umount $PWD/efi
rmdir efi

echo ""
echo " Next step will be to the to install and configure the target-vm"
echo ""
