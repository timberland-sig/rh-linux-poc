#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $DIR/defaults.sh

# Configuration
MODES="net"
MODE=""

set -e

display_help() {
        echo
        echo " Usage: ${0##*/} [-h] <$MODES>"
        echo
        echo "  -h            : display this help"
        echo ""
        echo "  net           : revert network environment configuration"
        echo "                : - removes bridge interfaces and NetworkManager connections"
        echo "                : - restores original network interface configurations"
        echo ""
        echo " Examples: "
        echo "  Revert network configuration"
        echo "       ./${0##*/} net "
        exit 1
}

shutdown_vms() {
	local DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	make -C $DIR/target-vm kill
	make -C $DIR/host-vm kill
}

revert_bridge_iface() {
    local br_name=$1

    echo " : Reverting bridge interface: $br_name"

    if nmcli dev show ${br_name} &>/dev/null ; then
        # Find all devices connected to this bridge
	#              find slaves of br_name     | get name    | trim leading whitespace
        local slaves=$(ip -o link show master ${br_name} | cut -d: -f2 | sed -e 's/^ *//')
	echo "slaves=$slaves"

        # Find the hypervisor-bridge connection
        local bridge_con=$(nmcli -t -f NAME,TYPE,DEVICE con show --active | grep ":bridge:${br_name}" | cut -d: -f1)
	echo "bridge_con=$bridge_con"

        for slave in $slaves; do
		# Find all bridge-slave connections
		local slave_conns=($(nmcli -t -f NAME,DEVICE,SLAVE con show | grep ":${slave}:bridge$" | cut -d: -f1))
		# Check all connections
		for conn in $(nmcli -t -f NAME con show) ; do
			if ! [ ${slave} = $(nmcli -g connection.interface-name con show ${conn}) ] ; then
				continue
			elif ! printf '%s\0' "${slave_conns[@]}" | grep -F -x -z -- "$conn" &>/dev/null ; then
				# Switch to the old non-bridged connection
				echo "   - Reconnectig ${slave} to ${conn}"
				sudo nmcli conn up ${conn}
				break
			fi
		done
		# Remove bridge-slave connections
		for conn in $slave_conns; do
		    echo "   - Removing bridge-slave connection: $conn"
		    sudo nmcli con down "$conn" || true
		    sudo nmcli con delete "$conn" || true
		done
        done

        # Remove the bridge
        if [ -n "$bridge_con" ]; then
            echo "   - Removing bridge connection: $bridge_con"
            sudo nmcli con down "$bridge_con" || true
	    sudo nmcli con delete "$bridge_con" || true
        fi

        echo "   - Bridge $br_name has been removed"
    else
        echo "   - Bridge $br_name does not exist, skipping"
    fi
}

revert_network() {
    echo " : Reverting bridged network environment"

    # Revert the bridges in reverse order of creation
    revert_bridge_iface "$BRIDGE2_NAME"
    revert_bridge_iface "$BRIDGE1_NAME"
    revert_bridge_iface "$BRIDGE0_NAME"

    echo ""
    echo "Network configuration reverted!"
    echo ""
    echo "Note: The SSH key at $DIR/.ssh/id_ecdsa was created by setup but is not removed"
    echo "      by this script as it may be in use. Remove it manually if needed."
    echo ""
    echo "nmcli dev"
    nmcli dev
    echo ""
    echo "nmcli conn"
    nmcli conn
}

while getopts "h" opt; do
        case "${opt}" in
                h)
                        display_help >&2
                        exit 0
                ;;
                *)
                        echo "  Invalid argument: -$OPTARG" >&2
                        echo "  Try: \"$0 -h\"" >&2
                        exit 1
                ;;
        esac
done

shift "$((OPTIND-1))"   # Discard the options and sentinel --

NEWARGS="$@"

MODE=$(echo "${NEWARGS}" | tr -t '/' ' ' | awk '{print $1}')

if [ -z "${MODE}" ]; then
     echo "Try: \"$0 -h\"" >&2
     exit 1
fi

case "${MODE}" in
    net)
		shutdown_vms
		revert_network
    ;;
    *)
        echo "  Invalid argument: $MODE" >&2
        echo "  Try: \"$0 -h\"" >&2
        exit 1
    ;;
esac

