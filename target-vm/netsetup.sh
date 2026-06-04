#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
VMNAME=$(basename $PWD)

. $DIR/../vm-lib/colors.sh

show-help() {
    echo ""
    echo " Usage: netsetup.sh [--gen-nqn] [IP_ADDRESS]"
    echo ""
    echo " Configures the network of $VMNAME"
    echo ""
    echo "  IP_ADDRESS   - Host interface IP address (default: localhost)"
    echo "  --gen-nqn    - Generate a fresh random subsystem NQN"
    echo ""
    echo " Environment variables:"
    echo "  SUBNQN       - Soft target NVMe subsystem NQN"
    echo "  NVME_NS_PATH - Optional: Path to the NVMe namespace to bind to the soft-target"
    echo "                 - Deduced from PCIe address if not specified"
    echo "  TARGET_CIDR2 - Soft target IP address in CIDR notation (default: 192.168.101.20/24)"
    echo "  TARGET_CIDR3 - Soft target IP address in CIDR notation (default: 192.168.110.20/24)"
    echo ""
    exit 0
}

NEW_SUBNQN=0
for arg in "$@"; do
    case "$arg" in
        -h|--help) show-help ;;
        --gen-nqn) NEW_SUBNQN=1 ;;
    esac
done

# Filter out flags to get positional IP_ADDRESS argument
for arg in "$@"; do
    case "$arg" in
        --*|-*) ;;
        *) TARGET_IP1="$arg"; break ;;
    esac
done
TARGET_IP1="${TARGET_IP1:-localhost}"

if [ "$NEW_SUBNQN" -eq 1 ]; then
    export SUBNQN="nqn.2014-08.org.nvmexpress:uuid:$(uuidgen)"
    echo -e "${YELLOW}Generated new subsystem NQN: $SUBNQN${NC}"
fi

echo "$TARGET_IP1" > .ip
$DIR/../vm-lib/netsetup.sh "$TARGET_IP1"
