#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
VMNAME=$(basename $PWD)

show-help() {
    echo ""
    echo " Usage: netsetup.sh [IP_ADDRESS]"
    echo ""
    echo " Configures the network of $VMNAME"
    echo ""
    echo "  IP_ADDRESS - Host interface IP address (default: localhost)"
    echo ""
    echo " Environment variables:"
    echo "  TARGET_CIDR2 - Soft target IP address in CIDR notation (default: 192.168.101.20/24)"
    echo "  TARGET_CIDR3 - Soft target IP address in CIDR notation (default: 192.168.110.20/24)"
    echo ""
    exit 0
}

[[ "$1" == "-h" || "$1" == "--help" ]] && show-help

TARGET_IP1="${1:-localhost}"

$DIR/../vm-lib/netsetup.sh "$TARGET_IP1"
