#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2025 John Meneghini <jmeneghi@redhat.com> All rights reserved.

show-help() {
	echo "Usage: $0"
	echo ""
	echo "Debug script for NVMe-oF target discovery over TCP."
	echo ""
	echo "Target IP addresses can be set via environment variables:"
	echo "  TARGET_IP2"
	echo "  TARGET_IP3"
	echo ""
	echo "IP addresses from defaults.sh are used by default."
	exit 0
}

[[ "$1" == "-h" || "$1" == "--help" ]] && usage

DIR="$(dirname -- "$(realpath -- "$0")")"
source $DIR/../defaults.sh
source $DIR/../vm-lib/common.sh

if [ -z "$TARGET_IP2" ] ; then
	split_cidr "$TARGET_CIDR2" TARGET_IP2 MASK
fi
if [ -z "$TARGET_IP3" ] ; then
	split_cidr "$TARGET_CIDR3" TARGET_IP3 MASK
fi
echo ": using $TARGET_IP2"
echo ":   and $TARGET_IP3"

sudo modprobe nvme_fabrics
sudo modprobe nvme_tcp
sudo nvme discover --hostnqn=$HOSTNQN --hostid="$HOSTID" --transport=tcp --traddr=$TARGET_IP2 --trsvcid=4420
sudo nvme discover --hostnqn=$HOSTNQN --hostid="$HOSTID" --transport=tcp --traddr=$TARGET_IP3 --trsvcid=4420
