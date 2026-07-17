#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../defaults.sh"

# shellcheck disable=SC1091
[ -f "$DIR/.env" ] && . "$DIR/.env"

# Target-side subnets (192.168.2x)
export TARGET1_IFACE="${TARGET1_IFACE:-eth3}"
export TARGET1_IP="${TARGET1_IP:-192.168.20.1}"
export TARGET1_NET="${TARGET1_NET:-192.168.20.0/24}"

export TARGET2_IFACE="${TARGET2_IFACE:-eth4}"
export TARGET2_IP="${TARGET2_IP:-192.168.21.1}"
export TARGET2_NET="${TARGET2_NET:-192.168.21.0/24}"

export TARGET3_IFACE="${TARGET3_IFACE:-eth5}"
export TARGET3_IP="${TARGET3_IP:-192.168.22.1}"
export TARGET3_NET="${TARGET3_NET:-192.168.22.0/24}"

# Host-side subnets (192.168.3x)
export HOST1_IFACE="${HOST1_IFACE:-eth6}"
export HOST1_IP="${HOST1_IP:-192.168.30.1}"
export HOST1_NET="${HOST1_NET:-192.168.30.0/24}"

export HOST2_IFACE="${HOST2_IFACE:-eth7}"
export HOST2_IP="${HOST2_IP:-192.168.31.1}"
export HOST2_NET="${HOST2_NET:-192.168.31.0/24}"

export HOST3_IFACE="${HOST3_IFACE:-eth8}"
export HOST3_IP="${HOST3_IP:-192.168.32.1}"
export HOST3_NET="${HOST3_NET:-192.168.32.0/24}"

export DNS_SERVERS="${DNS_SERVERS:-8.8.8.8, 8.8.4.4}"

# Derived values for templates and other scripts
for _role in TARGET HOST; do
	for _n in 1 2 3; do
		_ip_var="${_role}${_n}_IP"
		_net_var="${_role}${_n}_NET"
		_ip="${!_ip_var}"
		_base="${_ip%.*}"
		_mask="${!_net_var#*/}"
		export "${_role}${_n}_POOL=${_ip} - ${_base}.200"
		export "${_role}${_n}_RESIP=${_base}.2"
		export "${_role}_CIDR${_n}=${_base}.2/${_mask}"
	done
done

_update_env() {
	local file="$1" var="$2" val="$3"
	if grep -q "^${var}=" "$file" 2>/dev/null; then
		sed -i "s|^${var}=.*|${var}=\"${val}\"|" "$file"
	else
		echo "${var}=\"${val}\"" >> "$file"
	fi
}

_env_file="$DIR/../.env"
for _role in TARGET HOST; do
	for _n in 1 2 3; do
		_cidr_var="${_role}_CIDR${_n}"
		_update_env "$_env_file" "$_cidr_var" "${!_cidr_var}"
	done
done
unset _env_file

export INTERFACES="\"$TARGET1_IFACE\", \"$TARGET2_IFACE\", \"$TARGET3_IFACE\", \"$HOST1_IFACE\", \"$HOST2_IFACE\", \"$HOST3_IFACE\""
export TARGET_MAC1 TARGET_MAC2 TARGET_MAC3 HOST_MAC1 HOST_MAC2 HOST_MAC3

# Bridge network addresses (read from host interfaces)
for _i in 1 2; do
	_br_var="BRIDGE${_i}_NAME"
	_br_addr=$(ip -4 -o addr show "${!_br_var}" 2>/dev/null | awk '{print $4}')
	if [ -n "$_br_addr" ]; then
		_br_base="${_br_addr%.*}"
		_br_mask="${_br_addr#*/}"
		export "BRIDGE${_i}_NET=${_br_base}.0/${_br_mask}"
	fi
done

unset _update_env _env_file _cidr_var _role _n _ip_var _net_var _ip _base _mask _i _br_var _br_addr _br_base _br_mask
