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

# Install router's SSH key if it exists
ROUTER_SSH_KEY="$DIR/../.ssh/router/id_ecdsa.pub"
if [ -f "$ROUTER_SSH_KEY" ]; then
    echo "Installing router's SSH public key on $VMNAME..."
    ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i "$ROUTER_SSH_KEY" ssh://${SSH_TARGET}
    echo "Router SSH key installed on $VMNAME"
fi

# Install VM utilities to /usr/local/bin
echo "Installing VM utilities on $VMNAME..."
scp -i $DIR/../.ssh/id_ecdsa -o StrictHostKeyChecking=no $DIR/mac2iface scp://${SSH_TARGET}//usr/local/bin/
run_ssh $VMNAME "chmod +x /usr/local/bin/mac2iface"
echo "VM utilities installed on $VMNAME"

case "$VMNAME" in
    target-vm)
        if has_router; then
            if has_dhcpd; then
	        TARGET_CIDR1='dhcp'
                TARGET_CIDR2='dhcp'
                TARGET_CIDR3='dhcp'
            else
                # Static mode: use addresses from router/addresses.sh.
                # TARGET_CIDR1 is left empty (skipped by remote-netsetup.sh)
                # in dynamic mode, and also when there is no br0 on the
                # hypervisor: in that case net0/$TARGET_MAC1 is actually
                # QEMU usermode (SLIRP) networking, not the router's
                # TARGET1_NET subnet, and already has its own working
                # DHCP-assigned address/gateway/DNS that must not be
                # touched.
                if [ "$target_ip" = "localhost" ]; then
                    TARGET_CIDR1='dhcp'
                fi
                TARGET_CIDR2="${TARGET_CIDR2}"
                TARGET_CIDR3="${TARGET_CIDR3}"
            fi
        fi
        make -C "$VMDIR" .build/tcp.json
        scp -i $DIR/../.ssh/id_ecdsa -o StrictHostKeyChecking=no "${VMDIR}/.build/"{tcp.json,hosts.txt} $VMDIR/wipe-nvme.sh $VMDIR/setup-nvme-target.sh $VMDIR/nvmet-mods.conf $DIR/remote-netsetup.sh scp://${SSH_TARGET}
        run_ssh $VMNAME "
set -e
. remote-netsetup.sh $TARGET_MAC1 $TARGET_MAC2 $TARGET_MAC3 \"$TARGET_CIDR1\" \"$TARGET_CIDR2\" \"$TARGET_CIDR3\"
. setup-nvme-target.sh \"$NVME_NS_PATH\"
"
    ;;
    host-vm)
        if has_router; then
            if has_dhcpd; then
                HOST_CIDR1='dhcp'
                HOST_CIDR2='dhcp'
                HOST_CIDR3='dhcp'
            else
                # Static mode: use addresses from router/addresses.sh.
                # HOST_CIDR1 is left empty (skipped by remote-netsetup.sh)
                # in dynamic mode, and also when there is no br0 on the
                # hypervisor: in that case net0/$HOST_MAC1 is actually
                # QEMU usermode (SLIRP) networking, not the router's
                # HOST1_NET subnet, and already has its own working
                # DHCP-assigned address/gateway/DNS that must not be
                # touched.
                if [ "$target_ip" = "localhost" ]; then
                    HOST_CIDR1='dhcp'
                fi
                HOST_CIDR2="${HOST_CIDR2}"
                HOST_CIDR3="${HOST_CIDR3}"
            fi
        fi
        make -C "$VMDIR" .build/discovery.conf
        scp -i $DIR/../.ssh/id_ecdsa -o StrictHostKeyChecking=no ${VMDIR}/.build/* $DIR/../vm-lib/remote-netsetup.sh scp://${SSH_TARGET}
        run_ssh $VMNAME "\
            cp ./discovery.conf /etc/nvme/
	    . remote-netsetup.sh $HOST_MAC1 $HOST_MAC2 $HOST_MAC3 \"$HOST_CIDR1\" \"$HOST_CIDR2\" \"$HOST_CIDR3\""
    ;;
    *)
        # This should never be reached
        exit 500
    ;;
esac

# If router is running in static mode, configure DNS and routing
if has_router && ! has_dhcpd; then
    echo "Router is in static mode, configuring DNS and routing on $VMNAME..."

    # Determine the VM role, its router-side address, and set up template variables.
    # Note: the router reaches the VM over its own private network (virbr_*_0),
    # not via $target_ip, which is only routable from the hypervisor.
    case "$VMNAME" in
        target-vm)
            VM_RESIP="${TARGET1_RESIP}"
            export VM_ROLE="target"
            export GATEWAY_MAC="${TARGET_MAC1}"
            export GATEWAY_IP="${TARGET1_IP}"
            export MAC2="${TARGET_MAC2}"
            export MAC3="${TARGET_MAC3}"
            # Routes for TARGET: access HOST networks via TARGET interfaces
            export ROUTES2="nmcli con modify \"\$CONN2\" +ipv4.routes \"${HOST2_NET} ${TARGET2_IP}\" +ipv4.routes \"${BRIDGE1_NET} ${TARGET2_IP}\""
            export ROUTES3="nmcli con modify \"\$CONN3\" +ipv4.routes \"${HOST3_NET} ${TARGET3_IP}\" +ipv4.routes \"${BRIDGE2_NET} ${TARGET3_IP}\""
            ;;
        host-vm)
            VM_RESIP="${HOST1_RESIP}"
            export VM_ROLE="host"
            export GATEWAY_MAC="${HOST_MAC1}"
            export GATEWAY_IP="${HOST1_IP}"
            export MAC2="${HOST_MAC2}"
            export MAC3="${HOST_MAC3}"
            # Routes for HOST: access TARGET networks via HOST interfaces
            export ROUTES2="nmcli con modify \"\$CONN2\" +ipv4.routes \"${TARGET2_NET} ${HOST2_IP}\" +ipv4.routes \"${BRIDGE1_NET} ${HOST2_IP}\""
            export ROUTES3="nmcli con modify \"\$CONN3\" +ipv4.routes \"${TARGET3_NET} ${HOST3_IP}\" +ipv4.routes \"${BRIDGE2_NET} ${HOST3_IP}\""
            ;;
    esac
    export DNS_SERVERS

    # When there is no br0 on the hypervisor, net0/$GATEWAY_MAC is QEMU
    # usermode (SLIRP) networking rather than the router's primary subnet -
    # it already has its own working DHCP-assigned address/gateway/DNS, so
    # static-client-config.sh must leave that interface alone entirely.
    if [ "$target_ip" = "localhost" ]; then
        export SKIP_PRIMARY=1
    else
        export SKIP_PRIMARY=""
    fi

    # Render the script on the hypervisor (same pattern as kea-dhcp4.conf.in).
    # Only substitute the template placeholders explicitly listed below -
    # the script also contains its own runtime shell variables (e.g.
    # $GATEWAY_IFACE, $CONN2, $dev) that must be left untouched so the VM
    # evaluates them at execution time instead of envsubst blanking them
    # out here (envsubst replaces any *unset* $VAR it's allowed to touch
    # with an empty string).
    STATIC_CONFIG_VARS='$VM_ROLE $GATEWAY_MAC $GATEWAY_IP $MAC2 $MAC3 $ROUTES2 $ROUTES3 $DNS_SERVERS $SKIP_PRIMARY'
    ROUTER_SCRIPT_TEMPLATE="$DIR/../router/static-client-config.sh.in"
    if [ -f "$ROUTER_SCRIPT_TEMPLATE" ]; then
        envsubst "$STATIC_CONFIG_VARS" < "$ROUTER_SCRIPT_TEMPLATE" | run_ssh "$VMNAME" "
        cat - > /root/static-client-config.sh
        chmod 0755 /root/static-client-config.sh
	/root/static-client-config.sh
	"

        echo "Static network configuration applied to $VMNAME"
    fi
fi

echo ""
echo "Use \"ssh -i $(realpath $DIR/../.ssh/id_ecdsa) ssh://${SSH_TARGET}\" to login to the $VMNAME"
echo ""
