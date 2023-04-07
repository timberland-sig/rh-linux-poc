#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#
# Global variables
#
COPR_PROJECT=timberland-v14.2
COPR_USER=johnmeneghini

# These are the system-uuid, Hostnqn and Hostid for the target-vm
TARGETID="e1df2843-7f74-48c4-adb0-b2a5b9bab8f1"
# The TARGET_SYS_UUID is generated with TARGET_SYS_UUID="$(uuidgen)"
TARGET_SYS_UUID="a53caec2-eb2d-4bca-819e-f2bbfb10e1fa"
TARGETNQN="nqn.2014-08.org.nvmexpress:uuid:$TARGET_SYS_UUID"

# These are the system-uuid, Hostnqn and Hostid for the host-vm
HOSTID="4e16bbb4-097f-44be-8c7f-77d8b4fc9f39"
# This HostNQN appears in the target-vm/tcp.json file and in the host-vm/discover_target.sh file
# The HOST_SYS_UUID is generated with HOST_SYS_UUID="$(uuidgen)"
HOST_SYS_UUID="f8131bac-cdef-4165-866b-5998c1e67890"
HOSTNQN="nqn.2014-08.org.nvmexpress:uuid:$HOST_SYS_UUID"

# These are the Namespace identifiers and Subsystem NQN for the Linux Ctrl soft target.
# See the target-vm/tcp.json.in file for more information.
SUBNQN="nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db"
NSNGUID="ace42e00-1510-2fce-2ee4-ac0000000001"
NSUUID="bee9c2b7-1761-44b5-a4e6-0f690498a94b"

# Serial numbers for nvme disks, used by target-vm/install.sh
# Generated with SN=$(hexdump -vn8 -e'4/4 "%08X" 1 "\n"' /dev/urandom)

SN1=2AF557665E8B11C0
SN2=97A28D5D3ECDE7F2
SN3=3A44B3E2177CA6D9

# Note that TARGET_MAC1 and HOST_MAC1 are used with DHCP and must be unique to
# your testbed.  Use the ./gen_macaddr.py script and replace these values
# for your testbed.

TARGET_MAC1="CA:4B:D6:8D:94:01"
HOST_MAC1="CA:4B:D6:8E:94:01"

# The Following MAC and IP addresses are static and only used on the private
# virbr1 and virbr2 networks.  These can all be safely left and unchanged.

TARGET_MAC2="EA:EB:D3:56:89:56"
TARGET_MAC3="EA:EB:D3:57:89:57"
HOST_MAC2="EA:EB:D3:58:89:58"
HOST_MAC3="EA:EB:D3:59:89:59"

TARGET_IP2="192.168.101.20"
TARGET_IP3="192.168.110.20"
TARGET_CIDR2="$TARGET_IP2/24"
TARGET_CIDR3="$TARGET_IP3/24"

HOST_IP2="192.168.101.30"
HOST_IP3="192.168.110.30"
HOST_CIDR2="$HOST_IP2/24"
HOST_CIDR3="$HOST_IP3/24"

HOSTGW_IP2="192.168.101.1"
HOSTGW_IP3="192.168.110.1"
HOSTGW_CIDR2="$HOSTGW_IP2/24"
HOSTGW_CIDR3="$HOSTGW_IP3/24"

ISO_VERSIONS="fedora-36|fedora-37|fedora-38"
ISOVERSION_F36="Fedora-Everything-netinst-x86_64-36-1.5.iso"
ISOVERSION_F37="Fedora-Everything-netinst-x86_64-37-1.7.iso"
ISOVERSION_F38="Fedora-Everything-netinst-x86_64-38_Beta-1.3.iso"

OVMF_ZIP="timberland-ovmf-release-9e63dc0.zip"
OVMF_URL="https://github.com/timberland-sig/edk2/releases/download/release-9e63dc0/"

