#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
VMNAME=$(basename $PWD)

if [ $# -lt 1 ]; then
    echo ""
    echo " Usage: netsetup.sh <bridged|localhost>"
    echo ""
    echo " Configures the network of $VMNAME"
    echo ""
    echo "  bridged   - Use bridged networking (prompts for IP address)"
    echo "  localhost - Use localhost networking"
    echo ""
    exit 1
fi

NET_TYPE="$1"

# Validate parameter
if [[ "$NET_TYPE" != "localhost" && "$NET_TYPE" != "bridged" ]]; then
    echo "Error: parameter must be 'localhost' or 'bridged'"
    exit 1
fi

TARGET_IP1='localhost'
if [ "$NET_TYPE" = 'bridged' ]; then
    echo " Record the host interface name and ip address with \"ip -br address show\" command."
    echo ""
    read -p "Enter host interface IP address: " TARGET_IP1
fi

$DIR/../vm-lib/netsetup.sh "$TARGET_IP1"
