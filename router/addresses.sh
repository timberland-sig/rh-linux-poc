#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

# Scope DIR locally so it doesn't override the caller's DIR when sourced
_source_deps() {
	local DIR
	DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	. "$DIR/../defaults.sh"
	# shellcheck disable=SC1091
	[ -f "$DIR/.env" ] && . "$DIR/.env"
	_env_file="$DIR/../.env"
}
_source_deps

# Target-side subnets (192.168.2x)
export ROUTER_TO_TARGET_IFACE1="${ROUTER_TO_TARGET_IFACE1:-eth3}"
export ROUTER_TO_TARGET_IP1="${ROUTER_TO_TARGET_IP1:-192.168.20.1}"
export ROUTER_TO_TARGET_NET1="${ROUTER_TO_TARGET_NET1:-192.168.20.0/24}"

export ROUTER_TO_TARGET_IFACE2="${ROUTER_TO_TARGET_IFACE2:-eth4}"
export ROUTER_TO_TARGET_IP2="${ROUTER_TO_TARGET_IP2:-192.168.21.1}"
export ROUTER_TO_TARGET_NET2="${ROUTER_TO_TARGET_NET2:-192.168.21.0/24}"

export ROUTER_TO_TARGET_IFACE3="${ROUTER_TO_TARGET_IFACE3:-eth5}"
export ROUTER_TO_TARGET_IP3="${ROUTER_TO_TARGET_IP3:-192.168.22.1}"
export ROUTER_TO_TARGET_NET3="${ROUTER_TO_TARGET_NET3:-192.168.22.0/24}"

# Host-side subnets (192.168.3x)
export ROUTER_TO_HOST_IFACE1="${ROUTER_TO_HOST_IFACE1:-eth6}"
export ROUTER_TO_HOST_IP1="${ROUTER_TO_HOST_IP1:-192.168.30.1}"
export ROUTER_TO_HOST_NET1="${ROUTER_TO_HOST_NET1:-192.168.30.0/24}"

export ROUTER_TO_HOST_IFACE2="${ROUTER_TO_HOST_IFACE2:-eth7}"
export ROUTER_TO_HOST_IP2="${ROUTER_TO_HOST_IP2:-192.168.31.1}"
export ROUTER_TO_HOST_NET2="${ROUTER_TO_HOST_NET2:-192.168.31.0/24}"

export ROUTER_TO_HOST_IFACE3="${ROUTER_TO_HOST_IFACE3:-eth8}"
export ROUTER_TO_HOST_IP3="${ROUTER_TO_HOST_IP3:-192.168.32.1}"
export ROUTER_TO_HOST_NET3="${ROUTER_TO_HOST_NET3:-192.168.32.0/24}"

export DNS_SERVERS="${DNS_SERVERS:-8.8.8.8, 8.8.4.4}"

# Derived values for templates and other scripts
for _role in TARGET HOST; do
	for _n in 1 2 3; do
		_ip_var="ROUTER_TO_${_role}_IP${_n}"
		_net_var="ROUTER_TO_${_role}_NET${_n}"
		_ip="${!_ip_var}"
		_base="${_ip%.*}"
		_mask="${!_net_var#*/}"
		export "ROUTER_TO_${_role}_POOL${_n}=${_ip} - ${_base}.200"
		export "ROUTER_TO_${_role}_RESIP${_n}=${_base}.2"
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

for _role in TARGET HOST; do
	for _n in 1 2 3; do
		_cidr_var="${_role}_CIDR${_n}"
		_update_env "$_env_file" "$_cidr_var" "${!_cidr_var}"
	done
done
unset _env_file

export INTERFACES="\"$ROUTER_TO_TARGET_IFACE1\", \"$ROUTER_TO_TARGET_IFACE2\", \"$ROUTER_TO_TARGET_IFACE3\", \"$ROUTER_TO_HOST_IFACE1\", \"$ROUTER_TO_HOST_IFACE2\", \"$ROUTER_TO_HOST_IFACE3\""
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

unset _source_deps _update_env _cidr_var _role _n _ip_var _net_var _ip _base _mask _i _br_var _br_addr _br_base _br_mask
