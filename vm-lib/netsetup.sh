#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

set -e

DIR="$(dirname -- "$(realpath -- "$0")")"
echo "$DIR"
. $DIR/../defaults.sh
. $DIR/../vm-lib/common.sh

# Source router addresses if router is available
if has_router; then
    . $DIR/../router/addresses.sh
fi

VMNAME=${VMNAME:-$(basename -- $PWD)}
echo "VMNAME=${VMNAME}"
VMDIR="$DIR/../$VMNAME"
target_ip="$1"

if [ $# -lt 1 ] ; then
    echo " "
    echo " Usage: netsetup.sh <ipaddr | localhost>"
    echo " "
    echo " Configures the network of $VMNAME"
    echo " "
    echo "  ipaddr - dhcp assigned IPv4 address of $VMNAME"
    echo "           - corresponds to $BRIDGE0_NAME on the hypervisor host"
    echo ""
    echo "   Passing \"localhost\" in the ipaddr field is used with there is no $BRIDGE0_NAME interface"
    echo "   configured on the hypervisor. See \"./install.sh\" help for more information."
    echo ""
    echo "   E.g.:"
    echo "          $0 192.168.0.63"
    echo "          $0 10.16.188.66"
    echo "          $0 localhost"
    echo " "
    exit 1
fi

case "$VMNAME" in
    target-vm)
        SSH_PORT=$TARGET_PORT
    ;;
    host-vm)
        SSH_PORT=$HOST_PORT
    ;;
    *)
        echo "VM named $VMNAME is not recognized!" >&2
        exit 1
    ;;
esac

mkdir -p .build

mkdir -p $HOME/.ssh
touch $HOME/.ssh/known_hosts

SSH_TARGET="root@$target_ip"
SSH_KNOWN_HOST_ID="$target_ip"
case "$target_ip" in
    localhost)
        make -C "$VMDIR" -f "$DIR/Makefile" NET_TYPE=localhost .build/hosts.txt
        SSH_TARGET="${SSH_TARGET}:$SSH_PORT"
        SSH_KNOWN_HOST_ID="[localhost]:$SSH_PORT"
    ;;
    *)
        make -C "$VMDIR" -f "$DIR/Makefile" NET_TYPE=bridged .build/hosts.txt
    ;;
esac
chmod 644 "$VMDIR/.build/hosts.txt"

ssh-keygen -R "${SSH_KNOWN_HOST_ID}"
ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i $DIR/../.ssh/id_ecdsa.pub ssh://${SSH_TARGET}

case "$VMNAME" in
    target-vm)
        GATEWAY="" ROUTES2="" ROUTES3="" DNS_SERVERS=""
        if has_router; then
            if has_dhcpd; then
                TARGET_CIDR1='dhcp'
                TARGET_CIDR2='dhcp'
                TARGET_CIDR3='dhcp'
            else
                # Static mode: use addresses from router/addresses.sh.
                # TARGET_CIDR1 is forced to 'dhcp' only when there is no
                # br0 on the hypervisor: in that case net0/$TARGET_MAC1 is
                # actually QEMU usermode (SLIRP) networking, not the
                # router's TARGET1_NET subnet, and already has its own
                # working DHCP-assigned address/gateway/DNS that must not
                # be touched. GATEWAY/DNS_SERVERS are computed
                # unconditionally below - remote-netsetup.sh's dhcp code
                # path for an interface ignores them entirely, so this is
                # safe even in the SLIRP case.
                if [ "$target_ip" = "localhost" ]; then
                    TARGET_CIDR1='dhcp'
                fi
                TARGET_CIDR2="${TARGET_CIDR2}"
                TARGET_CIDR3="${TARGET_CIDR3}"
                GATEWAY="$TARGET1_IP"
                DNS_SERVERS="${DNS_SERVERS}"
                # Routes for TARGET: access HOST networks via TARGET interfaces
                ROUTES2="${HOST2_NET} ${TARGET2_IP}"
                [ -n "$BRIDGE1_NET" ] && ROUTES2="${ROUTES2}, ${BRIDGE1_NET} ${TARGET2_IP}"
                ROUTES3="${HOST3_NET} ${TARGET3_IP}"
                [ -n "$BRIDGE2_NET" ] && ROUTES3="${ROUTES3}, ${BRIDGE2_NET} ${TARGET3_IP}"
            fi
        fi
        make -C "$VMDIR" .build/tcp.json
        make -C "$VMDIR" -f "$DIR/Makefile" VMNAME="$VMNAME" \
            MAC1="$TARGET_MAC1" MAC2="$TARGET_MAC2" MAC3="$TARGET_MAC3" \
            IP1="$TARGET_CIDR1" IP2="$TARGET_CIDR2" IP3="$TARGET_CIDR3" \
            GATEWAY="$GATEWAY" ROUTES2="$ROUTES2" ROUTES3="$ROUTES3" \
            DNS_SERVERS="$DNS_SERVERS" \
            .build/remote-netsetup.sh
        scp -i $DIR/../.ssh/id_ecdsa -o StrictHostKeyChecking=no "${VMDIR}/.build/"{tcp.json,hosts.txt,remote-netsetup.sh} $VMDIR/wipe-nvme.sh $VMDIR/setup-nvme-target.sh $VMDIR/nvmet-mods.conf scp://${SSH_TARGET}
        run_ssh $VMNAME "
set -e
. remote-netsetup.sh
. setup-nvme-target.sh \"$NVME_NS_PATH\"
"
    ;;
    host-vm)
        GATEWAY="" ROUTES2="" ROUTES3="" DNS_SERVERS=""
        if has_router; then
            if has_dhcpd; then
                HOST_CIDR1='dhcp'
                HOST_CIDR2='dhcp'
                HOST_CIDR3='dhcp'
            else
                # Static mode: use addresses from router/addresses.sh.
                # HOST_CIDR1 is forced to 'dhcp' only when there is no br0
                # on the hypervisor: in that case net0/$HOST_MAC1 is
                # actually QEMU usermode (SLIRP) networking, not the
                # router's HOST1_NET subnet, and already has its own
                # working DHCP-assigned address/gateway/DNS that must not
                # be touched. GATEWAY/DNS_SERVERS are computed
                # unconditionally below - remote-netsetup.sh's dhcp code
                # path for an interface ignores them entirely, so this is
                # safe even in the SLIRP case.
                if [ "$target_ip" = "localhost" ]; then
                    HOST_CIDR1='dhcp'
                fi
                HOST_CIDR2="${HOST_CIDR2}"
                HOST_CIDR3="${HOST_CIDR3}"
                GATEWAY="$HOST1_IP"
                DNS_SERVERS="${DNS_SERVERS}"
                # Routes for HOST: access TARGET networks via HOST interfaces
                ROUTES2="${TARGET2_NET} ${HOST2_IP}"
                [ -n "$BRIDGE1_NET" ] && ROUTES2="${ROUTES2}, ${BRIDGE1_NET} ${HOST2_IP}"
                ROUTES3="${TARGET3_NET} ${HOST3_IP}"
                [ -n "$BRIDGE2_NET" ] && ROUTES3="${ROUTES3}, ${BRIDGE2_NET} ${HOST3_IP}"
            fi
        fi
        make -C "$VMDIR" .build/discovery.conf
        make -C "$VMDIR" -f "$DIR/Makefile" VMNAME="$VMNAME" \
            MAC1="$HOST_MAC1" MAC2="$HOST_MAC2" MAC3="$HOST_MAC3" \
            IP1="$HOST_CIDR1" IP2="$HOST_CIDR2" IP3="$HOST_CIDR3" \
            GATEWAY="$GATEWAY" ROUTES2="$ROUTES2" ROUTES3="$ROUTES3" \
            DNS_SERVERS="$DNS_SERVERS" \
            .build/remote-netsetup.sh
        scp -i $DIR/../.ssh/id_ecdsa -o StrictHostKeyChecking=no ${VMDIR}/.build/* scp://${SSH_TARGET}
        run_ssh $VMNAME "\
            cp ./discovery.conf /etc/nvme/
	    . remote-netsetup.sh"
    ;;
    *)
        # This should never be reached
        exit 500
    ;;
esac

echo ""
echo "Use \"ssh -i $(realpath $DIR/../.ssh/id_ecdsa) ssh://${SSH_TARGET}\" to login to the $VMNAME"
echo ""
