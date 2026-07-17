#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
VMNAME=$(basename $PWD)

. $DIR/../vm-lib/common.sh
. $DIR/../vm-lib/colors.sh

if has_router; then
    . $DIR/../router/addresses.sh
fi

. $DIR/../defaults.sh

show-help() {
    echo ""
    echo " Usage: netsetup.sh [--gen-nqn] [IP_ADDRESS]"
    echo ""
    echo " Configures the network of $VMNAME"
    echo ""
    echo "  IP_ADDRESS - Host interface IP address (default: localhost)"
    echo "  --gen-nqn  - Generate a fresh random host NQN"
    echo ""
    echo " Environment variables:"
    echo "  HOST_CIDR2 - Soft target IP address in CIDR notation (default: 192.168.101.30/24)"
    echo "  HOST_CIDR3 - Soft target IP address in CIDR notation (default: 192.168.110.30/24)"
    echo ""
    exit 0
}

GEN_NQN=0
for arg in "$@"; do
    case "$arg" in
        -h|--help) show-help ;;
        --gen-nqn) GEN_NQN=1 ;;
    esac
done

# Filter out flags to get positional IP_ADDRESS argument
for arg in "$@"; do
    case "$arg" in
        --*|-*) ;;
        *) HOST_IP1="$arg"; break ;;
    esac
done

if [ -z "$HOST_IP1" ]; then
    if [ -n "$(get_bridge_slaves ${BRIDGE0_NAME} 2>/dev/null)" ]; then
        read -rp "Enter the IP address of $VMNAME on $BRIDGE0_NAME: " HOST_IP1
        if [ -z "$HOST_IP1" ]; then
            echo -e "${RED}Error: IP address is required in bridged mode${NC}" >&2
            exit 1
        fi
    else
        HOST_IP1="localhost"
    fi
fi

if [ "$GEN_NQN" -eq 1 ]; then
    export HOSTNQN="nqn.2014-08.org.nvmexpress:uuid:$(uuidgen)"
    echo -e "${YELLOW}Generated new host NQN: $HOSTNQN${NC}"
    echo -e "${YELLOW}Host ID: $HOSTID${NC}"
fi

echo "$HOST_IP1" > .ip
$DIR/../vm-lib/netsetup.sh "$HOST_IP1"
