#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#echo "DIR = $DIR"
. $DIR/defaults.sh

# Configuraiton
MODES="user|devel|virt|net|edk2|iso"
MODE="user"

set -e

display_help() {
        echo
        echo " Usage: ${0##*/} [-h] <$MODES>"
        echo
        echo "  -h            : display this help"
        echo ""
        echo "  quickstart    : runs user, virt, net, edk2 and also iso if there is no ISO downloaded"
        echo "  user          : setup basic user environment (default)"
        echo "  devel         : setup development environment"
        echo "  virt          : install qemu-kvm environment "
        echo "  edk2          : download the timberland-sig modified edk2 firmware"
        echo "                : - install build artifacts in the host-vm directory"
        echo "                : - use -s or --source to build from source instead of downloading the prebuilt zip"
        echo "  net           : configure network environment "
        echo "                : - script prompts for \"bridged\" primary interface."
        echo "                :   Enter \"local\" to skip primary interace reconfiguration."
        echo "  iso           : download an ISO file of an OS you wish to install on the VMs from a URL"
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
            lorax-lmc-novirt pykickstart openssl make python3-pytest python3-jsonschema
        touch .usr
    else
        echo " : Nothing to do!"
    fi

    git submodule update --init host-vm/nvmeof-utils
}

install_devel() {

    echo " : Installing developer environment"

    if [ ! -f .devel ]; then
        sudo dnf group install -y development-tools
        sudo dnf install -y asciidoc audit-libs-devel binutils-devel elfutils-devel java-devel kabi-dw libcap-devel \
            libcap-ng-devel libmnl-devel llvm ncurses-devel newt-devel nss-tools numactl-devel pciutils-devel perl perl-generators \
            pesign python3-devel python3-docutils xmlto rpm-build yum-utils sg3_utils dwarves libbabeltrace-devel libbpf-devel openssl-devel \
            wget bison acpica-tools binutils gcc gcc-c++ meson cmake dbus-devel libuuid libuuid-devel \
            json-c-devel json-c json-c-doc clang openssl kmod-devel python3-sphinx python3-sphinx_rtd_theme swig \
            systemd-devel mock lorax tar gpg pciutils copr-cli nvme-cli nasm
        sudo usermod -a -G mock $USER

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

    bridge_iface 'br0' "$1" "$2"

    ip -h -c -o -br address show ${br_name}

    if ! nmcli dev show virbr1 &>/dev/null ; then
        # sudo nmcli conn add type bridge ifname virbr1 con-name virbr1 stp yes ipv4.addresses $HOSTGW_CIDR2 ipv4.method manual ipv6.method shared
	bridge_iface 'virbr1' "$3" "$4"
        ip -h -c -o -br address show virbr1
    fi

    if ! nmcli dev show virbr2 &>/dev/null ; then
        # sudo nmcli conn add ifname virbr2 type bridge con-name virbr2 stp yes ipv4.addresses $HOSTGW_CIDR3 ipv4.method manual ipv6.method shared
	bridge_iface 'virbr2' "$5" "$6"
        ip -h -c -o -br address show virbr2
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

install_edk2() {
    pushd $DIR
    if [ ! -d edk2 ]; then
        mkdir -p edk2
        pushd edk2
        git clone -b timberland_upstream-dev-full git@github.com:timberland-sig/edk2.git
        pushd edk2
        git config url."ssh://git@github.com/timberland-sig".insteadOf https://github.com/timberland-sig
        git submodule update --init --recursive
        popd
        popd
    fi
    pushd edk2/edk2
    make -C BaseTools clean
    rm -rf Build
    make -C BaseTools
    source edksetup.sh
    build -t GCC5 -a X64 -p OvmfPkg/OvmfPkgX64.dsc
    mkdir -p $DIR/ISO
    rm -f  $DIR/host-vm/OVMF_CODE.fd
    rm -f  $DIR/host-vm/vm_vars.fd
    rm -f  $DIR/host-vm/eficonfig/NvmeOfCli.efi
    rm -f  $DIR/host-vm/eficonfig/VConfig.efi
    cp -fv Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd $DIR/host-vm/OVMF_CODE.fd
    cp -fv Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd $DIR/host-vm/vm_vars.fd
    cp -fv Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd $DIR/ISO/OVMF_VARS.fd
    cp -fv Build/OvmfX64/DEBUG_GCC5/X64/VConfig.efi $DIR/host-vm/eficonfig/VConfig.efi
    cp -fv Build/OvmfX64/DEBUG_GCC5/X64/NvmeOfCli.efi $DIR/host-vm/eficonfig/NvmeOfCli.efi
    popd
}

install_edk2_zip() {
    pushd $DIR

    if [ ! -d ISO ]; then
        mkdir -p ISO
    fi

    if [ ! -f ISO/$OVMF_ZIP ]; then
        pushd ISO
        wget --no-check-certificate  $OVMF_URL/$OVMF_ZIP
        unzip $OVMF_ZIP
        popd
    fi

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

install_prebuilt_iso() {
    pushd $DIR
    if [ ! -f .pkgs2 ]; then
        sudo dnf -y install vim tar wget net-tools zip unzip
        touch .pkgs2
    fi
    if [ ! -d ISO ]; then
        mkdir -p ISO
    fi

	touch .durl
	touch .diso

    # https://mirror.stream.centos.org/10-stream/BaseOS/x86_64/iso/
    # https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/
    # https://download.eng.rdu.redhat.com/rhel-9/composes/RHEL-9/
    # https://download.eng.rdu.redhat.com/rhel-10/composes/RHEL-10/
    # https://dl.fedoraproject.org/pub/fedora/linux/releases/42/Everything/x86_64/os/

    DOWNLOAD_URL="$(cat .durl)"
    read -r -p "Enter URL of the ISO or DVD ($DOWNLOAD_URL): " INPUT
    if [ -z "$INPUT" ]; then
        INPUT="$DOWNLOAD_URL"
    fi
    DOWNLOAD_URL="$INPUT"
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "No URL provided"
        exit 1
    fi
    echo "$DOWNLOAD_URL" > .durl
    ISONAME=$(echo $DOWNLOAD_URL | awk -F/ '{print $NF}' | cut -d'?' -f1)
    if [ -z "$ISONAME" ]; then
        echo "No .iso found"
        exit 1
    fi

    # Ensure filename ends with .iso if it contains .iso
    if [[ "$ISONAME" == *.iso* ]]; then
        ISONAME="${ISONAME%.iso*}.iso"
    fi

    if [ ! -f ISO/$ISONAME ]; then
        pushd ISO
        echo "wget ${DOWNLOAD_URL}"
        wget --no-check-certificate -O ${ISONAME} ${DOWNLOAD_URL}
		if [ $? -eq 0 ]; then
			echo "${ISONAME}" > $DIR/.diso
		fi
        popd
    else
		echo "ISO $ISONAME already exists"
		echo "${ISONAME}" > $DIR/.diso
	fi
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
        if [ ! -f .diso ] ; then
            install_prebuilt_iso
        fi
    ;;
    test)
        pushd target-vm
        make rh-start QEMU_ARGS="-vnc :0"
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
        # Check for -s or --source flag
        if [[ "$2" == "-s" || "$2" == "--source" ]]; then
            install_edk2
        else
            install_edk2_zip
        fi
    ;;
    iso)
        install_prebuilt_iso
    ;;
    *)
    echo "  Invalid argument: $MODE" >&2
    echo "  Try: \"$0 -h\"" >&2
    exit 1
    ;;
esac
