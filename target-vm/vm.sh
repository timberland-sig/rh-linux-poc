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
    echo "  -F, --foreground        Run QEMU in foreground instead of backgrounding (default: background)"
    echo "  --vnc[=DISPLAY]         Use VNC for VM display (optional display number, default: :0)"
    echo "  --graphical             Use graphical display (X11/Wayland)"
    echo ""
    echo "Examples:"
    echo "  $0 install disks/boot.qcow2                      # Install with localhost networking"
    echo "  $0 -i custom.iso install disks/boot.qcow2        # Install using custom.iso"
    echo "  $0 -n 1 start disks/boot.qcow2                   # Start with 1 extra drive"
    echo "  $0 install disks/boot.qcow2                      # Install with bridged networking"
    echo "  $0 -F start disks/boot.qcow2                     # Start in foreground"
    echo "  $0 -n 3 start disks/boot.qcow2                   # Start with 3 extra drives"
    echo "  $0 -n 2 -i custom.iso install disks/boot.qcow2   # Multiple options combined"
    echo "  $0 --vnc start disks/boot.qcow2                  # Start with VNC on display :0"
    echo "  $0 --vnc=:2 start disks/boot.qcow2               # Start with VNC on display :2"
    echo "  $0 --graphical install disks/boot.qcow2          # Install with graphical display"
}

HOST=`hostname`
VMNAME=`basename $PWD`
QEMU=none
BRIDGE_HELPER=none
QARGS=""
ISO_FILE=""
N_EXTRA_DRIVES=0
RUN_FOREGROUND=false
_DISPLAY_ARGS=()

# Parse options using getopt
PARSED=$(getopt --options hi:n:F --longoptions help,iso:,extra-drives:,foreground,vnc::,graphical --name "$0" -- "$@")
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
        -F|--foreground)
            RUN_FOREGROUND=true
            shift 1
            ;;
        --vnc)
            _DISPLAY_ARGS=(--vnc)
            if [ -n "$2" ]; then
                VNC_DISPLAY="${2#:}"
            fi
            shift 2
            ;;
        --graphical)
            _DISPLAY_ARGS=(--graphical)
            shift
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

# Detect a bridged setup
if [ -n "$(get_bridge_slaves ${BRIDGE0_NAME} 2>/dev/null)" ] ; then
        NET0_NET="-netdev bridge,br=$BRIDGE0_NAME,id=net0,helper=$BRIDGE_HELPER"
        NET0_DEV="-device virtio-net-pci,netdev=net0,mac=$TARGET_MAC1,addr=4"
else
        NET0_NET="-netdev user,id=net0,hostfwd=tcp::$TARGET_PORT-:22"
        NET0_DEV="-device e1000e,netdev=net0,addr=4"
        echo "$TARGET_PORT" > .netport
fi

NET1_NET="-netdev bridge,br=$BRIDGE1_NAME,id=net1,helper=$BRIDGE_HELPER"
NET1_DEV="-device rtl8139,netdev=net1,mac=$TARGET_MAC2,addr=5"
NET2_NET="-netdev bridge,br=$BRIDGE2_NAME,id=net2,helper=$BRIDGE_HELPER"
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

DISPLAY_ARGS=""
if [[ "$MODE" == "install" && "$RUN_FOREGROUND" == "true" ]]; then
    DISPLAY_ARGS="-serial stdio -display none"
else
    # Check if -vnc was already specified via QARGS pass-through
    _vnc_in_qargs=false
    for _qarg in $QARGS; do
        if [ "$_qarg" = "-vnc" ]; then
            _vnc_in_qargs=true
            break
        fi
    done

    if ! $_vnc_in_qargs; then
        resolve_display_mode "${_DISPLAY_ARGS[@]}"
        if [ "$DISPLAY_MODE" = "vnc" ]; then
            VNC_DISPLAY="${VNC_DISPLAY:-0}"
            DISPLAY_ARGS="-vnc :${VNC_DISPLAY}"
        fi
    fi
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
$NET2_DEV \
$DISPLAY_ARGS
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
