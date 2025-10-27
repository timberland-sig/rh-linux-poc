#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../global_vars.sh
. $DIR/../vm_lib.sh

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    VM_NAME=$(basename $PWD)
    echo "Usage: $0 MODE BOOT_DISK [NET_CONN] [N_EXTRA_DRIVES] [QARGS]"
    echo "   or: $0 MODE BOOT_DISK [N_EXTRA_DRIVES] [QARGS]"
    echo "   or: $0 MODE BOOT_DISK [QARGS]"
    echo ""
    echo "Install or start a Linux distribution on the $VM_NAME with configurable networking."
    echo ""
    echo "Arguments:"
    echo "  MODE            Operation mode: 'install' or 'start' (required)"
    echo "  BOOT_DISK       Path to the boot disk image (required)"
    echo "  NET_CONN        Network connection type: 'localhost' or 'bridged' (default: localhost)"
    echo "  N_EXTRA_DRIVES  Number of additional NVMe drives to create (default: 0)"
    echo "                  The $VM_NAME always gets 2 base NVMe drives (boot and NBFT)"
    echo "  QARGS           Optional extra commands for QEMU"
    echo ""
    echo "Examples:"
    echo "  $0 install disks/boot.qcow2                        # Install $VM_NAME on disks/boot.qcow2 with localhost networking"
    echo "  $0 start disks/boot.qcow2 1                        # Start $VM_NAME with localhost networking, 1 extra drive"
    echo "  $0 install disks/boot.qcow2 bridged                # Install $VM_NAME with bridged networking"
    echo "  $0 start disks/boot.qcow2 localhost 3              # Start $VM_NAME with localhost networking, 3 extra drives"
    echo "  $0 install disks/boot.qcow2 localhost 0 -vnc :0    # Install $VM_NAME with a VNC connection"
    echo "  $0 install disks/boot.qcow2 localhost 0 -vnc :0    # Start $VM_NAME with a VNC connection"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    exit 0
fi

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE_HELPER=none
QARGS=""
ISO_FILE=""

# Check if MODE and BOOT_DISK arguments are provided
if [ $# -lt 2 ]; then
    echo "Error: MODE and BOOT_DISK arguments are required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Parse parameters
MODE="$1"
BOOT_DISK="$2"
shift 2

# Validate MODE
if [[ "$MODE" != "install" && "$MODE" != "start" ]]; then
    echo "Error: MODE must be 'install' or 'start'"
    exit 1
fi

if [[ "$1" == "localhost" || "$1" == "bridged" ]]; then
    NET_CONN="$1"
    N_EXTRA_DRIVES=${2:-0}
    shift 2 && QARGS=$@
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    NET_CONN="localhost"
    N_EXTRA_DRIVES="$1"
    shift 1
    QARGS=$@
else
    NET_CONN="localhost"
    N_EXTRA_DRIVES=${1:-0}
    shift 1
    QARGS=$@
fi

# Only find ISO for install mode
if [[ "$MODE" == "install" ]]; then
    find_iso
fi
check_qemu_command

if [ ! -f "$BOOT_DISK" ]; then
    echo "Error: Boot disk '$BOOT_DISK' not found!"
    exit 1
else
    BOOT_DISK=$(realpath $BOOT_DISK)
    echo "using $BOOT_DISK"
fi

case "$NET_CONN" in
    localhost)
        # NET0_NET="-netdev user,id=net0,net=$NET_CIDR,hostfwd=tcp::$NET_PORT-:22"
        NET0_NET="-netdev user,id=net0,hostfwd=tcp::$TARGET_PORT-:22"
        NET0_DEV="-device e1000,netdev=net0,addr=4"
        echo "$TARGET_PORT" > .netport
    ;;
    bridged)
        NET0_NET="-netdev bridge,br=br0,id=net0,helper=$BRIDGE_HELPER"
        NET0_DEV="-device virtio-net-pci,netdev=net0,mac=$TARGET_MAC1,addr=4"
    ;;
    *)
        echo " Error: invalid argument $NET_CONN"
        exit 1
    ;;
esac

check_qargs

NET1_NET="-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE_HELPER"
NET1_DEV="-device virtio-net-pci,netdev=net1,mac=$TARGET_MAC2,addr=5"
NET2_NET="-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE_HELPER"
NET2_DEV="-device virtio-net-pci,netdev=net2,mac=$TARGET_MAC3,addr=6"

# Set boot options based on mode
if [ "$MODE" == "install" ]; then
    BOOT_OPTIONS="-boot order=cd -cdrom $ISO_FILE"
fi

if [ "$MODE" == "start" ]; then
    NBFT_DISK=$(find . -name nvme1.qcow2 -print)
    if [ -z "$NBFT_DISK" ]; then
        echo "nvme1.qcow2 not found!"
        exit 1
    else
        NBFT_DISK=$(realpath $NBFT_DISK)
        echo "using $NBFT_DISK"
    fi

    NBFT_DRIVE_OPTIONS=$(cat << EOF
-device nvme,drive=NVME2,addr=0x08,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1
-drive file=$NBFT_DISK,if=none,id=NVME2
EOF
    )
fi

EXTRA_NVMES=()
for ((i=1; i<=N_EXTRA_DRIVES; i++)); do
    NVME_ID=$((i + 2))
    ADDR=$((0x0b + i - 1))
    EXTRA_DISK="disks/nvme${NVME_ID}.qcow2"
    make $EXTRA_DISK DRIVE_CAP=20G
    EXTRA_NVMES+=("-device nvme,drive=NVME${NVME_ID},bus=pcie.0,addr=0x$(printf '%x' $ADDR),max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$(generate_serial_number) -drive file=$(realpath $EXTRA_DISK),if=none,id=NVME${NVME_ID}")
done

$QEMU -name $VMNAME -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host -m 4G -smp 4 $QARGS \
-uuid $TARGET_SYS_UUID \
$BOOT_OPTIONS \
-device nvme,drive=NVME1,addr=0x07,max_ioqpairs=4,physical_block_size=4096,use-intel-id=on,serial=$SN0 \
-drive file=$BOOT_DISK,if=none,id=NVME1 \
$NBFT_DRIVE_OPTIONS \
${EXTRA_NVMES[@]} \
$NET0_NET \
$NET0_DEV \
$NET1_NET \
$NET1_DEV \
$NET2_NET \
$NET2_DEV &

disown %1

if [[ "$MODE" == "install" ]]; then
    echo ""
    echo " Be sure to create the root account with ssh access."
    echo " Reboot to complete the install and login to the root account."
    echo ""
    echo " Record the host interface name and ip address with \"ip -br address show\" command."
    echo ""
    echo " Next step will be to run the \"./netsetup.sh\" script."
    echo ""
elif [[ "$MODE" == "start" ]]; then
    echo -e "\e[32mThe $VMNAME is running in the background.\e[0m"
    echo ""
fi
