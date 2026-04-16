#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../defaults.sh
. $DIR/../vm-lib/common.sh
. $DIR/../vm-lib/colors.sh

show-help() {
    VM_NAME=$(basename $PWD)
    echo "Usage: $0 [OPTIONS] MODE BOOT_DISK [-- [QARGS]]"
    echo ""
    echo "Install or start a Linux distribution on the $VM_NAME with configurable networking."
    echo ""
    echo "Arguments:"
    echo "  MODE            Operation mode: 'install' or 'start' (required)"
    echo "  BOOT_DISK       Path to the boot disk image (required)"
    echo "  QARGS           Optional extra commands for QEMU"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message and exit"
    echo "  -i, --iso PATH          Path to ISO file for installation (only used in install mode)"
    echo "                          If not provided, find_iso function will locate an ISO automatically"
    echo "  -n, --extra-drives N    Number of additional NVMe drives to create (default: 0)"
    echo "                          The $VM_NAME always gets 2 base NVMe drives (boot and NBFT)"
    echo "  -c, --conn-type TYPE    Network connection type: 'localhost' or 'bridged' (default: localhost)"
    echo "  -F, --foreground        Run QEMU in foreground instead of backgrounding (default: background)"
    echo ""
    echo "Examples:"
    echo "  $0 install disks/boot.qcow2                              # Install with localhost networking"
    echo "  $0 -i custom.iso install disks/boot.qcow2                # Install using custom.iso"
    echo "  $0 -n 1 start disks/boot.qcow2                           # Start with 1 extra drive"
    echo "  $0 -c bridged install disks/boot.qcow2                   # Install with bridged networking"
    echo "  $0 -F start disks/boot.qcow2                             # Start in foreground"
    echo "  $0 -n 3 -c localhost start disks/boot.qcow2              # Start with 3 extra drives"
    echo "  $0 install disks/boot.qcow2 -- -vnc :0                   # Install with a VNC connection"
    echo "  $0 -n 2 -i custom.iso -c bridged install disks/boot.qcow2 # Multiple options combined"
}

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE_HELPER=none
QARGS=""
ISO_FILE=""
N_EXTRA_DRIVES=0
NET_CONN="localhost"
RUN_FOREGROUND=false

# Parse options using getopt
PARSED=$(getopt --options hi:n:c:F --longoptions help,iso:,extra-drives:,conn-type:,foreground --name "$0" -- "$@")
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments"
    echo "Use -h or --help for usage information"
    exit 1
fi

eval set -- "$PARSED"

# Extract options
while true; do
    case "$1" in
        -h|--help)
            show-help
            exit 0
            ;;
        -i|--iso)
            ISO_FILE="$2"
            shift 2
            ;;
        -n|--extra-drives)
            N_EXTRA_DRIVES="$2"
            shift 2
            ;;
        -c|--conn-type)
            NET_CONN="$2"
            shift 2
            ;;
        -F|--foreground)
            RUN_FOREGROUND=true
            shift 1
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error: Unexpected option: $1"
            exit 1
            ;;
    esac
done

# Check if MODE and BOOT_DISK arguments are provided
if [ $# -lt 2 ]; then
    echo "Error: MODE and BOOT_DISK arguments are required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Parse positional parameters
MODE="$1"
BOOT_DISK="$2"
shift 2

# Validate MODE
if [[ "$MODE" != "install" && "$MODE" != "start" ]]; then
    echo "Error: MODE must be 'install' or 'start'"
    exit 1
fi

# Validate NET_CONN
if [[ "$NET_CONN" != "localhost" && "$NET_CONN" != "bridged" ]]; then
    echo "Error: --conn-type must be 'localhost' or 'bridged'"
    exit 1
fi

# Remaining arguments are QARGS
check_qargs
QARGS="$QARGS $@"

# Only find ISO for install mode if not already provided
if [[ "$MODE" == "install" && -z "$ISO_FILE" ]]; then
    find_iso
elif [[ "$MODE" == "install" && -n "$ISO_FILE" ]]; then
    # Validate that the provided ISO file exists
    if [ ! -f "$ISO_FILE" ]; then
        echo "Error: ISO file '$ISO_FILE' not found!"
        exit 1
    fi
    ISO_FILE=$(realpath "$ISO_FILE")
    echo "using ISO: $ISO_FILE"
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

NET1_NET="-netdev bridge,br=virbr1,id=net1,helper=$BRIDGE_HELPER"
NET1_DEV="-device rtl8139,netdev=net1,mac=$TARGET_MAC2,addr=5"
NET2_NET="-netdev bridge,br=virbr2,id=net2,helper=$BRIDGE_HELPER"
NET2_DEV="-device rtl8139,netdev=net2,mac=$TARGET_MAC3,addr=6"

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
-device nvme,drive=NVME2,addr=0x08,max_ioqpairs=4,physical_block_size=4096,logical_block_size=4096,use-intel-id=on,serial=$SN1 \
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

# Check if VNC is enabled in QARGS
VNC_DISPLAY=""
QARGS_ARRAY=($QARGS)
VNC_IN_QARGS=false
for ((i=0; i<${#QARGS_ARRAY[@]}; i++)); do
    if [[ "${QARGS_ARRAY[$i]}" == "-vnc" ]]; then
        VNC_IN_QARGS=true
        VNC_ARG="${QARGS_ARRAY[$((i+1))]}"
        # Extract display number from formats like ":0", "127.0.0.1:0", etc.
        if [[ "$VNC_ARG" =~ :([0-9]+)$ ]]; then
            VNC_DISPLAY="${BASH_REMATCH[1]}"
        fi
        break
    fi
done

# Auto-enable VNC if no graphical interface is available
if [[ -z "$DISPLAY" && "$VNC_IN_QARGS" == "false" ]]; then
    QARGS="$QARGS -vnc :0"
    VNC_DISPLAY="0"
fi

mkdir -p $PWD/.build
cat - > .build/start-vm.sh << EOF
$QEMU -name $VMNAME -M q35 -accel kvm -bios OVMF-pure-efi.fd -cpu host -m 4G -smp 4 $QARGS \
-uuid $TARGET_SYS_UUID \
$BOOT_OPTIONS \
-device nvme,drive=NVME1,addr=0x07,max_ioqpairs=4,physical_block_size=4096,use-intel-id=on,serial="$SN0" \
-drive file=$BOOT_DISK,if=none,id=NVME1 \
$NBFT_DRIVE_OPTIONS \
${EXTRA_NVMES[@]} \
$NET0_NET \
$NET0_DEV \
$NET1_NET \
$NET1_DEV \
$NET2_NET \
$NET2_DEV
EOF

chmod +x .build/start-vm.sh

if [ -n "$VNC_DISPLAY" ]; then
    VNC_PORT=$((5900 + VNC_DISPLAY))
    echo ""
    echo " To connect to the $VMNAME over VNC, run: vncviewer $HOST:$VNC_PORT"
    echo ""
fi

if $RUN_FOREGROUND; then
    . .build/start-vm.sh
else
    . .build/start-vm.sh &
    disown %1
fi

if [[ "$MODE" == "install" ]]; then
    echo ""
    echo " Be sure to create the root account with ssh access."
    echo " Reboot to complete the install and login to the root account."
    echo " Then run:"
    echo " ./netsetup.sh localhost "
    echo ""
elif [[ "$MODE" == "start" ]]; then
    if $RUN_FOREGROUND; then
        echo -e "${GREEN}The $VMNAME is running in the foreground.${NC}"
    else
        echo -e "${GREEN}The $VMNAME is running in the background.${NC}"
    fi
fi
