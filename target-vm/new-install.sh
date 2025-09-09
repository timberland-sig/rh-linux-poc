#!/bin/bash

source ../global_vars.sh
source ../vm_lib.sh

find_iso

BOOT_DISK=$(find . -name boot.qcow2 -print)
if [ -z "$BOOT_DISK" ]; then
    echo " $BOOT_DISK not found!"
    exit 1
else
    BOOT_DISK=$(realpath $BOOT_DISK)
    echo "using $BOOT_DISK"
fi

virt-install \
    --name $(basename $PWD) \
    --uuid $TARGET_SYS_UUID \
    --vcpus 4 \
    --ram 4096 \
    --boot loader=/usr/share/OVMF/OVMF_CODE.fd,loader_secure=no \
    --qemu-commandline="-device nvme,drive=NVME1,bus=pcie.0,addr=0x07,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN0 -drive file=$BOOT_DISK,if=none,id=NVME1" \
    --network passt,portForward=127.0.0.1:$TARGET_PORT:22 \
    --network bridge=virbr1,mac=$MAC2,model=virtio \
    --network bridge=virbr2,mac=$MAC3,model=virtio \
    --check mac_in_use=off \
    --location $ISO_FILE \
    --initrd-inject ./anaconda-ks.cfg \
    --extra-args 'inst.ks=file:/anaconda-ks.cfg inst.text' \
    --console pty,target.type=virtio
