#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

# NOTE: caller must include global_vars.sh before including this file.

# validate that the interface is connected
function check_conn() {
    local iface="$1"

    if [ -z "$iface" ]; then
        echo "Error: No interface specified" >&2
        return 2
    fi

    # Check if interface exists
    if ! nmcli dev show "$iface" &>/dev/null ; then
        echo "Error: Interface '$iface' not found" >&2
        return 2
    fi

    # Get the device state
    local state=$(nmcli -t -f DEVICE,STATE dev status | grep "^${iface}:" | cut -d: -f2)

    case "$state" in
        connected|connecting)
            echo "Interface '$iface' is up (state: $state)"
            return 0
            ;;
        disconnected|unavailable|unmanaged)
            echo "Interface '$iface' is down (state: $state)"
            return 1
            ;;
        *)
            echo "Interface '$iface' has unknown state: $state"
            return 1
            ;;
    esac
}

check_qargs() {
    if [  -f .qargs ]; then
        QARGS="$(cat .qargs)"
        NUM=$(echo "$QARGS" | cut -d ':' -f 2)
        echo ""
        echo "Connect to console with \"vncviewer $HOST:$NUM\""
    fi
}

check_qemu_command() {
    echo -n "using "
    if ! command -v qemu-system-x86_64 ; then
        echo " qemu-system-x86_64 is not installed"
        exit 1
    fi

    QEMU="$(command -v qemu-system-x86_64)"
    if [[ $QEMU =~ "/usr/local" ]]; then
            BRIDGE_HELPER="/usr/local/libexec/qemu-bridge-helper"
    else
            BRIDGE_HELPER="/usr/libexec/qemu-bridge-helper"
    fi
}

find_iso() {
    ISOVERSION="$(cat ../.diso)"
    ISO_FILE=$(find ../ -name $ISOVERSION -print)
    if [ -z "$ISO_FILE" ]; then
	echo " Error: $ISOVERSION not found"
	echo " run \"setup.sh -m iso\" or \"setup.sh prebuilt\""
	exit 1
    else
        ISO_FILE=$(realpath $ISO_FILE)
        echo "using $ISO_FILE"
    fi
}

generate_serial_number() {
    hexdump -vn8 -e'4/4 "%08X" 1 "\n"' /dev/urandom
}

bridge_iface() {
    local br_name=$1

    if ! nmcli dev show ${br_name} &>/dev/null ; then
        netdev=""
        nmcli dev status
        echo ""
        read -r -p "Enter name of the network interface to bridge with ${br_name} or \"local\" to skip configuration: " netdev

        if [ -z netdev ]; then
            exit 1
        fi

        if [[ "$netdev" == *"local"* ]]; then
            echo " : local - skipping bridged network setup"
	    sudo nmcli conn add type bridge ifname ${br_name} con-name ${br_name} stp yes autoconnect yes
	    local br_conn=${br_name}
        else
            if ! nmcli dev show $netdev &>/dev/null ; then
                echo "Interface '$netdev' does not exist!"
                exit 1
            fi
	    # ip link set $netdev promisc on

	    local MAC=$(nmcli -t -f general.hwaddr -e yes dev show $netdev | sed 's/^GENERAL.HWADDR://')
	    local br_conn="${br_name}"
	    sudo nmcli dev down $netdev || true
	    sudo nmcli con add type bridge ifname ${br_name} con-name ${br_name} autoconnect yes stp off ethernet.cloned-mac-address $MAC
	    sudo nmcli con add type bridge-slave ifname $netdev con-name bridge-slave-${netdev} master ${br_name}
	    sudo nmcli con up ${br_name}
	    sudo nmcli con up bridge-slave-${netdev}
        fi
	case ${br_name} in
	    virbr1)
		    local ip_addr_default=$HOSTGW_CIDR2;;
            virbr2)
                    local ip_addr_default=$HOSTGW_CIDR3;;
            *)
                    local ip_addr_default='dhcp';;
        esac
	echo ""
	read -r -p "Enter the IP address in CIDR notation of the hypervisor (this machine) on the ${br_name} network or \"dhcp\" to keep dynamic addressing (default: ${ip_addr_default}): " ip_addr

	ip_addr=${ip_addr:-$ip_addr_default}
        if [ ${ip_addr} = 'dhcp' ]; then
	    sudo nmcli conn modify ${br_conn} ipv4.method auto ipv6.method shared
            return 0
	elif [ ${netdev} != 'local' ] ; then
	    sudo nmcli conn modify ${br_conn} ipv4.method manual ipv6.method shared ipv4.addresses ${ip_addr}
	    sudo nmcli dev reapply ${br_conn}
	fi
    fi
}
