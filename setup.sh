#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.
#
# vim: set tabstop=4 shiftwidth=4 expandtab :
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#echo "DIR = $DIR"
. $DIR/defaults.sh

# Configuraiton
MODES="user|devel|virt|net|edk2"
MODE="user"

set -e

display_help() {
        echo
        echo " Usage: ${0##*/} [-h] <$MODES>"
        echo
        echo "  -h            : display this help"
        echo ""
        echo "  quickstart    : runs user, virt, net, edk2_zip"
        echo "  user          : setup basic user environment (default)"
        echo "  devel         : setup development environment"
        echo "  virt          : install qemu-kvm environment "
        echo "  edk2_zip      : install lastest timberland-sig edk2 release"
        echo "  edk2          : git clone timberland-sig edk2 repo"
        echo "                : - build and install artifacts in the host-vm directory"
        echo "  net           : configure network environment "
        echo "                : - script prompts for \"bridged\" primary interface."
        echo "                :   Enter \"none\" to skip primary interace reconfiguration."
        echo ""
        echo " Examples: "
        echo "  Install qemu and configure hypervisor networks"
        echo "       ./${0##*/} virt "
        echo "       ./${0##*/} net "
        exit 1
}

install_user() {
    echo " : Installing user environment"

    if [ ! -f .usr ]; then
        sudo dnf install -y vim git wget ethtool net-tools zip unzip NetworkManager \
            lorax-lmc-novirt pykickstart openssl make python3-pytest python3-jsonschema \
            python3 python3-blessed python3-paramiko python3-scp xterm xorg-x11-xauth
        touch .usr
    else
        echo " : Nothing to do!"
    fi

    git submodule update --init host-vm/nvmeof-utils
}

install_devel_pkgs() {
    if [ ! -f .edk2pkgs ]; then
        sudo dnf group install -y development-tools
        sudo dnf install -y asciidoc audit-libs-devel binutils-devel elfutils-devel java-devel kabi-dw libcap-devel \
            libcap-ng-devel libmnl-devel llvm ncurses-devel newt-devel nss-tools numactl-devel pciutils-devel perl perl-generators \
            pesign python3-devel python3-docutils xmlto rpm-build yum-utils sg3_utils dwarves libbabeltrace-devel libbpf-devel openssl-devel \
            wget bison acpica-tools binutils gcc gcc-c++ meson cmake dbus-devel libuuid libuuid-devel \
            json-c-devel json-c json-c-doc clang openssl kmod-devel python3-sphinx python3-sphinx_rtd_theme swig \
            systemd-devel mock lorax tar gpg pciutils copr-cli nvme-cli nasm
        sudo usermod -a -G mock $USER
        touch .edk2pkgs
    fi
}

install_devel() {

    if [ ! -f .devel ]; then
        echo " : Installing developer environment"

        install_devel_pkgs

        if [ ! -f ~/.gitconfig ]; then
            echo " : You must setup ~/.gitconfig"
            exit 1
        fi

        if [ ! -d ~/.ssh ]; then
            echo " : You must setup setup ~/.ssh"
            exit 1
        else
            ssh -o StrictHostKeyChecking=no -T git@github.com
            if [ $? -ne 1 ]; then
                echo " : You must setup your ssh key for github.com"
                exit 1
            fi
        fi

        if [ ! -f ~/.config/copr ]; then
            echo " : You must setup setup ~/.config/copr"
            exit 1
        fi

        FOO="$(copr-cli whoami)"
        if [ -z "$FOO" ]; then
            echo " : No copr user found! "
            exit 1
        fi

        touch .devel
    fi

    if [ ! -f .macaddr ]; then
        FOO="$(./gen_macaddr.py)"
        if [ -z "$FOO" ]; then
            echo " : gen_macaddr.py failed! "
            exit 1
        else
            sed -i "s/^TARGET_MAC1.*/TARGET_MAC1\=$FOO/" defaults.sh
        fi
        FOO="$(./gen_macaddr.py)"
        if [ -z "$FOO" ]; then
            echo " : gen_macaddr.py failed! "
            exit 1
        else
            sed -i "s/^HOST_MAC1.*/HOST_MAC1\=$FOO/" defaults.sh
        fi

        touch .macaddr
    fi

    git submodule update --init --recursive

}

install_network() {

    echo " : setup bridged network environment"

    source $DIR/vm-lib/common.sh

    bridge_iface --optional "$BRIDGE0_NAME" "$1" "$2"

    ip -h -c -o -br address show ${BRIDGE0_NAME} 2>/dev/null || true

    if ! nmcli dev show "$BRIDGE1_NAME" &>/dev/null ; then
	    bridge_iface "$BRIDGE1_NAME" "$3" "$4"
        ip -h -c -o -br address show "$BRIDGE1_NAME"
    fi

    if ! nmcli dev show "$BRIDGE2_NAME" &>/dev/null ; then
	    bridge_iface "$BRIDGE2_NAME" "$5" "$6"
        ip -h -c -o -br address show "$BRIDGE2_NAME"
    fi

    echo "Network interfaces configured!"

    # Make SSH key for password-less login
    make --makefile="$DIR/vm-lib/Makefile" .ssh/id_ecdsa
}

install_virt() {
    if ! command -v qemu-system-x86_64 ; then
        sudo dnf install -y qemu-kvm qemu-img
    fi
    echo "allow all" > /tmp/bridge.conf
    sudo cp /tmp/bridge.conf /etc/qemu/bridge.conf
    sudo chmod 4755 /usr/libexec/qemu-bridge-helper
}

clean_edk2() {
    pushd $DIR
    if [ ! -d ISO ]; then
        mkdir -p ISO
    else
        rm -f  ISO/OVMF_CODE.fd
        rm -f  ISO/OVMF_VARS.fd
        rm -f  ISO/NvmeOfCli.efi
        rm -f  ISO/VConfig.efi
    fi
    popd
}

install_edk2_to_host() {
    pushd $DIR

    if [ ! -f ISO/OVMF_CODE.fd ]; then
        echo "file ISO/OVMF_CODE.fd not found!"
        exit 1
    fi

    rm -f  host-vm/OVMF_CODE.fd
    rm -f  host-vm/vm_vars.fd
    rm -f  host-vm/eficonfig/NvmeOfCli.efi
    rm -f  host-vm/eficonfig/VConfig.efi
    cp -fv ISO/OVMF_CODE.fd host-vm/OVMF_CODE.fd
    cp -fv ISO/OVMF_VARS.fd host-vm/vm_vars.fd
    cp -fv ISO/NvmeOfCli.efi host-vm/eficonfig/NvmeOfCli.efi
    cp -fv ISO/VConfig.efi host-vm/eficonfig/VConfig.efi
    popd
}

install_edk2() {
    pushd $DIR

    install_devel_pkgs

    if [ ! -d edk2 ]; then
        mkdir -p edk2
        pushd edk2
        # Timberland currently has two different release candidate branches to test.
        # Either one of these branches should work.
        # git clone -b dev-spdk-integration3 https://github.com/timberland-sig/edk2.git
        git clone -b rel/timberland_1_0_1 git@github.com:timberland-sig/edk2.git
        pushd edk2
        # The following is not needed with the dev-spdk-integration3 or rel/timberland_1_0_1 branch.
        # git config url."ssh://git@github.com/timberland-sig".insteadOf https://github.com/timberland-sig
        git submodule update --init --recursive
        popd
        popd
    fi
    pushd edk2/edk2
    make -C BaseTools clean
    rm -rf Build
    rm -f build.log
    make -C BaseTools
    source edksetup.sh
    build -t GCC -a X64 -p OvmfPkg/OvmfPkgX64.dsc -D NETWORK_SNP_ENABLE=FALSE -D NETWORK_IP6_ENABLE=FALSE \
        -D NETWORK_ISCSI_ENABLE=FALSE -D NETWORK_PXE_BOOT_ENABLE=FALSE 2>&1 | tee -a build.log

    clean_edk2

    rm -f  $DIR/ISO/$OVMF_ZIP

    cp -fv Build/OvmfX64/DEBUG_GCC/FV/OVMF_CODE.fd $DIR/ISO/OVMF_CODE.fd
    cp -fv Build/OvmfX64/DEBUG_GCC/FV/OVMF_VARS.fd $DIR/ISO/OVMF_VARS.fd
    cp -fv Build/OvmfX64/DEBUG_GCC/X64/VConfig.efi $DIR/ISO/VConfig.efi
    cp -fv Build/OvmfX64/DEBUG_GCC/X64/NvmeOfCli.efi $DIR/ISO/NvmeOfCli.efi

    install_edk2_to_host

    popd
}

install_edk2_zip() {
    pushd $DIR

    clean_edk2

    if [ ! -f ISO/$OVMF_ZIP ]; then
        pushd ISO
        wget --no-check-certificate  $OVMF_URL/$OVMF_ZIP
        popd
    fi

    if [ ! -f ISO/OVMF_CODE.fd ]; then
        pushd ISO
        unzip $OVMF_ZIP
        popd
    fi

    install_edk2_to_host

    popd
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
MODE=$(echo "$@" | tr -t '/' ' ' | awk '{print $1}')

if [ -z "${MODE}" ]; then
     echo "Try: \"$0 -h\"" >&2
fi

shift 1
NEWARGS="$@"

case "${MODE}" in
    quick*)
        install_user
        install_virt
        install_edk2_zip
        install_network
    ;;
    test)
        pushd target-vm
        make auto-start QEMU_ARGS="-vnc :0"
        popd
        pushd host-vm
        make setup QEMU_ARGS="-vnc :1"
        popd
    ;;
    user)
        install_user
    ;;
    devel)
        install_devel
    ;;
    virt)
        install_virt
    ;;
    net)
        install_network $NEWARGS
    ;;
    edk2)
	install_edk2
    ;;
    edk2_zip)
	install_edk2_zip
    ;;
    *)
    echo "  Invalid argument: $MODE" >&2
    echo "  Try: \"$0 -h\"" >&2
    exit 1
    ;;
esac
