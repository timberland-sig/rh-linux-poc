#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2026 Michal Rábek <mrabek@redhat.com> All rights reserved.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$DIR/vm-lib/colors.sh"

display_help() {
    echo
    echo " Usage: ${0##*/} [-h]"
    echo
    echo "  -h    : display this help"
    echo
    echo " Shows the current status of the test environment:"
    echo "  - IP addresses of all network interfaces"
    echo "  - Current edk2 source code remote and branch"
    echo "  - Running state of all VMs (target-vm, host-vm, router-vm)"
    echo
    exit 0
}

edk2_info() {
    local edk2_dir="$DIR/edk2/edk2"

    if [ ! -d "$edk2_dir/.git" ]; then
        echo "edk2: not cloned"
        return
    fi

    local remote branch remote_url
    remote=$(git -C "$edk2_dir" remote | head -1)
    remote_url=$(git -C "$edk2_dir" remote get-url "$remote" 2>/dev/null)
    branch=$(git -C "$edk2_dir" branch --show-current 2>/dev/null)
    branch=${branch:-"(detached HEAD)"}

    echo "EDK2"
    echo "----"
    echo "remote: $remote_url"
    echo "branch: $branch"
}

vm_status() {
    local vms=("target-vm" "host-vm" "router-vm")
    local dirs=("$DIR/target-vm" "$DIR/host-vm" "$DIR/router")

    printf "%-12s %s\n" "VM" "STATUS"
    printf "%-12s %s\n" "---" "------"

    for i in "${!vms[@]}"; do
        local status
        status=$(make -C "${dirs[$i]}" --no-print-directory is-running 2>/dev/null)
        if [ "$status" = "YES" ]; then
            printf "%-12s ${GREEN}%s${NC}\n" "${vms[$i]}" "RUNNING"
        else
            printf "%-12s ${RED}%s${NC}\n" "${vms[$i]}" "STOPPED"
        fi
    done
}

while getopts "h" opt; do
    case "${opt}" in
        h)
            display_help
            ;;
        *)
            echo "  Invalid argument: -$OPTARG" >&2
            echo "  Try: \"$0 -h\"" >&2
            exit 1
            ;;
    esac
done

echo ""
ip -h -c -o -br address show
echo ""
edk2_info
echo ""
vm_status
echo ""
