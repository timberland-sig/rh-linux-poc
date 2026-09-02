#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

# NOTE: caller must include defaults.sh before including this file.

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

# validate IPv4 CIDR notation
validate_cidr() {
    local cidr="$1"

    # Check if CIDR notation format is correct (xxx.xxx.xxx.xxx/yy)
    if ! [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi

    # Extract IP address and prefix length
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"

    # Validate prefix length (0-32 for IPv4)
    if [ "$prefix" -lt 0 ] || [ "$prefix" -gt 32 ]; then
        return 1
    fi

    # Validate each octet of the IP address (0-255)
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    return 0
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
    if [ ! -f $PWD/.diso ]; then
        echo " Error: no ISO configured for $(basename $PWD)"
        echo " run \"make iso\" in this directory first"
        exit 1
    fi
    ISOVERSION="$(cat $PWD/.diso)"
    ISO_FILE=$(find ../ -name $ISOVERSION -print)
    if [ -z "$ISO_FILE" ]; then
        echo " Error: $ISOVERSION not found"
        echo " run \"make iso\" in this directory first"
        exit 1
    else
        ISO_FILE=$(realpath $ISO_FILE)
        echo "using $ISO_FILE"
    fi
}

# Convert CIDR prefix length to dotted decimal subnet mask
cidr_to_netmask() {
    local prefix="$1"
    local mask=""
    local full_octets=$((prefix / 8))
    local partial_octet=$((prefix % 8))

    # Add full octets (255)
    for ((i=0; i<full_octets; i++)); do
        mask="${mask}255."
    done

    # Add partial octet if needed
    if [ $partial_octet -gt 0 ]; then
        local value=$((256 - 2**(8-partial_octet)))
        mask="${mask}${value}."
    fi

    # Fill remaining octets with 0
    while [ $(echo -n "$mask" | tr -cd '.' | wc -c) -lt 4 ]; do
        mask="${mask}0."
    done

    # Remove trailing dot
    echo "${mask%.}"
}

# Validate subnet mask (accepts both CIDR bits and dotted decimal)
# Returns 0 if valid, 1 if invalid
validate_subnet_mask() {
    local mask="$1"

    # Check if it's a number (CIDR notation)
    if [[ "$mask" =~ ^[0-9]+$ ]]; then
        if [ "$mask" -ge 1 ] && [ "$mask" -le 31 ]; then
            return 0
        fi
        return 1
    fi

    # Check if it's dotted decimal format
    if ! [[ "$mask" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Validate each octet (0-255)
    local IFS='.'
    local -a octets=($mask)
    if [ ${#octets[@]} -ne 4 ]; then
        return 1
    fi

    for octet in "${octets[@]}"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    # Validate that it's a valid subnet mask (contiguous 1s followed by 0s)
    local binary=""
    for octet in "${octets[@]}"; do
        binary="${binary}$(printf '%08d' $(echo "obase=2; $octet" | bc))"
    done

    # Check for pattern: 1s followed by 0s
    if ! [[ "$binary" =~ ^1*0*$ ]] || [[ "$binary" =~ ^0+$ ]]; then
        return 1
    fi

    return 0
}

# Normalize subnet mask to dotted decimal format
# Converts CIDR bits to dotted decimal if needed
normalize_subnet_mask() {
    local mask="$1"

    # If it's a number, convert to dotted decimal
    if [[ "$mask" =~ ^[0-9]+$ ]]; then
        cidr_to_netmask "$mask"
    else
        echo "$mask"
    fi
}

split_cidr() {
    if [ $# -lt 3 ]; then
        cat <<EOF
Usage: split_cidr <IP_ADDR_CIDR> <IP_VAR_NAME> <MASK_VAR_NAME>

Splits the provided CIDR IP address into its two components by the slash character.

Arguments:
  IP_ADDR_CIDR      Valid IP address with mask in CIDR format
  IP_VAR_NAME       Name of the variable to store the address part into
  MASK_VAR_NAME     Name of the variable to store the mask into

If any of these two variables does not exist yet, it is created.
If the IP address on input is not in valid CIDR, the behavior is undefined.
EOF
        return 1
    fi

    local ip_addr=$1
    local -n ip_addr_var=$2
    local -n ip_mask_var=$3

    ip_addr_var=$(echo "$ip_addr" | cut -d'/' -f1)
    ip_mask_var=$(echo "$ip_addr" | cut -d'/' -f2)
}

generate_serial_number() {
    hexdump -vn8 -e'4/4 "%08X" 1 "\n"' /dev/urandom
}

resolve_display_mode() {
    local _cli_mode=""
    local _project_root
    _project_root="$(dirname -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")")"
    local _state_file="$_project_root/.display_mode"

    DISPLAY_MODE=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --vnc)
                _cli_mode="vnc"
                shift
                ;;
            --graphical)
                _cli_mode="graphical"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -n "$_cli_mode" ]; then
        DISPLAY_MODE="$_cli_mode"
        return 0
    fi

    if [ -f "$_state_file" ]; then
        DISPLAY_MODE="$(cat "$_state_file")"
        return 0
    fi

    if [ -t 0 ]; then
        echo "No display mode configured. Select display mode:"
        echo "  1) VNC"
        echo "  2) Graphical"
        while true; do
            read -r -p "Choice [1]: " _answer
            case "$_answer" in
                ""|1)
                    DISPLAY_MODE="vnc"
                    echo "vnc" > "$_state_file"
                    break
                    ;;
                2)
                    DISPLAY_MODE="graphical"
                    echo "graphical" > "$_state_file"
                    break
                    ;;
            esac
        done
        return 0
    fi

    DISPLAY_MODE="vnc"
}

bridge_iface() {
    local br_name=""
    local netdev=""
    local ip_addr=""
    local _optional=false

    # Parse flags
    while [[ "${1:-}" == -* ]]; do
        case "$1" in
            -h|--help)
                cat <<EOF
Usage: bridge_iface [--optional] BRIDGE_NAME [SLAVE_INTERFACE] [IP_ADDRESS]

Configure a network bridge using NetworkManager.

Arguments:
  BRIDGE_NAME       Name of the bridge interface (e.g., $BRIDGE0_NAME, br1, br2)
  SLAVE_INTERFACE   Network interface to bridge (optional)
                    - Use 'none' to create bridge without a slave interface
                    - If not provided, will prompt interactively
  IP_ADDRESS        IPv4 address in CIDR notation or 'dhcp' (optional)
                    - If not provided, will prompt interactively
                    - Default for br1: $HOSTGW_CIDR2
                    - Default for br2: $HOSTGW_CIDR3
                    - Default for others: dhcp

Options:
  --optional        Skip bridge creation entirely when the slave interface
                    is 'none' (instead of creating a bridge without a slave)
  -h, --help        Show this help message

Examples:
  bridge_iface $BRIDGE0_NAME eth0 192.168.1.1/24
  bridge_iface --optional $BRIDGE0_NAME eth0     # skip if user says 'none'
  bridge_iface br1 none dhcp
  bridge_iface br2 enp2s0
  bridge_iface $BRIDGE0_NAME                     # Interactive mode

Note: If the bridge already exists, this function will skip configuration.
EOF
                return 0
                ;;
            --optional)
                _optional=true
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Parse positional arguments
    br_name="$1"
    netdev="$2"
    ip_addr="$3"

    if [ -z "$br_name" ]; then
        echo "Error: Bridge name is required" >&2
        echo "Try: bridge_iface --help" >&2
        return 1
    fi

    # Check if bridge already exists
    if nmcli dev show "${br_name}" &>/dev/null ; then
        echo "Bridge ${br_name} already exists, skipping configuration"
        return 0
    fi

    # Interactive prompt for network device if not provided
    if [ -z "$netdev" ]; then
        ip -br addr show
        echo ""
        read -r -p "Enter name of the network interface to bridge with ${br_name} or \"none\" to skip configuration: " netdev

        if [ -z "$netdev" ]; then
            echo "Error: No network device specified" >&2
            return 1
        fi
    fi

    # Capture existing IP before the interface is brought down
    local _existing_ip=""

    # Create bridge based on whether it's none or bridged
    if [[ "$netdev" == *"none"* ]]; then
        if $_optional; then
            echo " : ${br_name} - skipping optional bridge (no device specified)"
            return 0
        fi
        echo " : local - skipping bridged network setup"
        sudo nmcli conn add type bridge ifname ${br_name} con-name ${br_name} stp yes autoconnect yes
        local br_conn=${br_name}
    else
        if ! nmcli dev show $netdev &>/dev/null ; then
            echo "Interface '$netdev' does not exist!" >&2
            return 1
        fi
        # ip link set $netdev promisc on

        local MAC=$(nmcli -t -f general.hwaddr -e yes dev show $netdev | sed 's/^GENERAL.HWADDR://')
        local _ip_method
        _ip_method=$(nmcli -t -f ipv4.method con show "$(nmcli -t -f GENERAL.CONNECTION dev show "$netdev" | cut -d: -f2)" 2>/dev/null)
        if [[ "$_ip_method" == *"manual"* ]]; then
            _existing_ip=$(ip -4 -o addr show dev "$netdev" 2>/dev/null | awk '{print $4}' | head -1)
	elif [[ "$_ip_method" == *"auto"* ]]; then
            _existing_ip="dhcp"
        fi
        local br_conn="${br_name}"
        sudo nmcli dev down $netdev || true
        sudo nmcli con add type bridge ifname ${br_name} con-name ${br_name} autoconnect yes stp off ethernet.cloned-mac-address $MAC
        sudo nmcli con add type bridge-slave ifname $netdev con-name bridge-slave-${netdev} master ${br_name}
        sudo nmcli con up ${br_name}
        sudo nmcli con up bridge-slave-${netdev}
    fi

    # Determine default IP address: prefer the slave NIC's existing IP
    if [ -n "$_existing_ip" ]; then
        local ip_addr_default="$_existing_ip"
    else
        case ${br_name} in
            "$BRIDGE1_NAME")
                local ip_addr_default=$HOSTGW_CIDR2;;
            "$BRIDGE2_NAME")
                local ip_addr_default=$HOSTGW_CIDR3;;
            *)
                local ip_addr_default='dhcp';;
        esac
    fi

    # Interactive prompt for IP address if not provided
    if [ -z "$ip_addr" ]; then
        echo ""
        while true; do
            read -r -p "Enter the IP address in CIDR notation of the hypervisor (this machine) on the ${br_name} network or \"dhcp\" to keep dynamic addressing (default: ${ip_addr_default}): " ip_addr
            ip_addr=${ip_addr:-$ip_addr_default}
            if [ "${ip_addr}" = 'dhcp' ] || validate_cidr "${ip_addr}"; then
                break
            fi
            echo "Error: Invalid CIDR notation. Please enter a valid IPv4 address in CIDR format (e.g., 192.168.101.1/24) or \"dhcp\"."
        done
    else
        # Validate the provided IP address
        if [ "${ip_addr}" != 'dhcp' ] && ! validate_cidr "${ip_addr}"; then
            echo "Error: Invalid CIDR notation: ${ip_addr}" >&2
            echo "Please enter a valid IPv4 address in CIDR format (e.g., 192.168.101.1/24) or \"dhcp\"." >&2
            return 1
        fi
    fi

    # Configure IP address
    if [ ${ip_addr} = 'dhcp' ]; then
        sudo nmcli conn modify ${br_conn} ipv4.method auto ipv6.method shared
        return 0
    else
        sudo nmcli conn modify ${br_conn} ipv4.method manual ipv6.method shared ipv4.addresses ${ip_addr}
        sudo nmcli dev reapply ${br_conn}
    fi
}

get_bridge_slaves() {
        local br_name="$1"
        ip -o link show master "$br_name" | cut -d: -f2 | sed -e 's/^ *//'
        return 0
}

has_router() {
        DIR="$(dirname -- "$(realpath -- "$BASH_SOURCE[0]")")"

	command -v incus && \
		[ "$(incus info router-vm 2>/dev/null | grep '^Status:' | cut -d' ' -f2)" = 'RUNNING' ]
}

# NOTE: caller must set `target_ip` before calling this function.
run_ssh() {
    local vmname="$1"
    shift

    local ssh_port
    case "$vmname" in
        target-vm)
            ssh_port=$TARGET_PORT
            ;;
        host-vm)
            ssh_port=$HOST_PORT
            ;;
        *)
            echo "VM named $vmname is not recognized!" >&2
            return 1
            ;;
    esac

    local _project_root
    _project_root="$(dirname -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")")"

    local ssh_target="root@${target_ip}"
    if [ "$target_ip" = "localhost" ]; then
        ssh_target="${ssh_target}:${ssh_port}"
    fi

    ssh -t -i "${_project_root}/.ssh/id_ecdsa" -o StrictHostKeyChecking=no "ssh://${ssh_target}" "$@"
}
