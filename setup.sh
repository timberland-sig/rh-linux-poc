#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#echo "DIR = $DIR"
. $DIR/global_vars.sh

# Configuraiton
MODES="user|devel|virt|net|edk2|iso"
MODE="user"

ALL_VERSIONS="fedora-36|fedora-37|fedora-42|centos-stream-9|opensuse-tumbleweed"


display_help() {
        echo
        echo " Usage: ${0##*/} [-h] [-m ] <$MODES> [$ALL_VERSIONS]"
        echo
        echo "  -h            : display this help"
        echo "  -m            : use mock to build things"
        echo ""
        echo "  user          : setup basic user environment (default)"
        echo "  devel         : setup development environment"
        echo "  virt          : install qemu-kvm environment "
        echo "  edk2          : create and build the timberland-sig edk2 repository in the edk2 directory "
        echo "                : - install build artifacts in OVMF directory  "
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
        sudo dnf install -y vim git wget ethtool net-tools zip unzip nmcli
        touch .usr
    else
        echo " : Nothing to do!"
    fi
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
        else
            sed -i "s/^COPR_USER.*/COPR_USER\=$FOO/" global_vars.sh
        fi

        touch .devel
    fi

    if [ ! -f .macaddr ]; then
        FOO="$(./gen_macaddr.py)"
        if [ -z "$FOO" ]; then
            echo " : gen_macaddr.py failed! "
            exit 1
        else
            sed -i "s/^TARGET_MAC1.*/TARGET_MAC1\=$FOO/" global_vars.sh
        fi
        FOO="$(./gen_macaddr.py)"
        if [ -z "$FOO" ]; then
            echo " : gen_macaddr.py failed! "
            exit 1
        else
            sed -i "s/^HOST_MAC1.*/HOST_MAC1\=$FOO/" global_vars.sh
        fi

        touch .macaddr
    fi

    git submodule update --init --recursive

}

# validate that the interface is connected
function check_conn () {
    set -o pipefail # optional.
    nmcli conn show --active | grep -q "$1"
}

install_network() {

    echo " : setup bridged network environment"

    nmcli dev show br0 &>/dev/null
    if [ $? -ne 0 ]; then
        netdev=""
        nmcli dev status
        echo ""
        read -r -p "enter name of default network managment device or \"local\" to skip configuration: " netdev

        if [ -z netdev ]; then
            exit 1
        fi

        if [[ "$netdev" == *"local"* ]]; then
            echo " : local - skipping default bridged network setup"
        else
            nmcli dev show $netdev &>/dev/null
            if [ $? -ne 0 ]; then
                echo "Interface $netdev does not exist!"
                exit 1
            fi

            if check_conn $netdev; then
                MAC=$(nmcli -t -f general.hwaddr -e yes dev show $netdev | sed 's/^GENERAL.HWADDR://')
                sudo nmcli con down $netdev
                sudo nmcli con add type bridge ifname br0 autoconnect yes stp off ethernet.cloned-mac-address $MAC
                sudo nmcli con add type bridge-slave ifname $netdev master br0
                sudo nmcli con up bridge-br0
                sudo nmcli con up bridge-slave-$netdev
            else
                echo "Interface $netdev is down!"
                echo " try: nmcli con add type ethernet ifname $netdev con-name $netdev autoconnect yes"
               exit 1
            fi

            set -
            MAC=$(nmcli -t -f general.hwaddr -e yes dev show $netdev | sed 's/^GENERAL.HWADDR://')
            sudo nmcli con down $netdev
            sudo nmcli con add type bridge ifname br0 autoconnect yes stp off ethernet.cloned-mac-address $MAC
            sudo nmcli con add type bridge-slave ifname $netdev master br0
            sudo nmcli con up bridge-br0
            ip -h -c -o -br address show br0
            set +
        fi
    fi

    nmcli dev show virbr1 &>/dev/null
    if [ $? -ne 0 ]; then
        sudo nmcli conn add type bridge ifname virbr1 con-name virbr1 stp yes ipv4.addresses $HOSTGW_CIDR2 ipv4.method manual ipv6.method shared
        ip -h -c -o -br address show virbr1
    fi

    nmcli dev show virbr2 &>/dev/null
    if [ $? -ne 0 ]; then
        sudo nmcli conn add ifname virbr2 type bridge con-name virbr2 stp yes ipv4.addresses $HOSTGW_CIDR3 ipv4.method manual ipv6.method shared
        ip -h -c -o -br address show virbr2
    fi
}

install_virt() {
    command -v qemu-system-x86_64
    if [ $? -ne 0 ]; then
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

	if [ ! -f .pkgs ]; then
		sudo dnf install -y wget zip unzip
	fi

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
    read -r -p "Enter URL of the ISO or DVD ($DOWNLOAD_URL) :" INPUT
    if [ -z "$INPUT" ]; then
        INPUT="$DOWNLOAD_URL"
    fi
    DOWNLOAD_URL="$INPUT"
    if [ -z "$DOWNLOAD_URL" ]; then
        echo "No URL provided"
        exit 1
    fi
    ISOVERSION=$(echo $DOWNLOAD_URL | awk -F/ '{print $NF}')
    if [ -z "$ISOVERSION" ]; then
        echo "No .iso found"
        exit 1
    fi

    if [ ! -f ISO/$ISOVERSION ]; then
        pushd ISO
        echo "wget ${DOWNLOAD_URL}"
        wget --no-check-certificate ${DOWNLOAD_URL}
		if [ $? -eq 0 ]; then
			echo "${ISOVERSION}" > $DIR/.diso
		fi
        popd
    else
		echo "ISO $ISOVERSION already exists"
		echo "${ISOVERSION}" > $DIR/.diso
	fi
}

while getopts "mh" opt; do
        case "${opt}" in
                h)
                        display_help >&2
                        exit 0
                ;;
                m)
                        MOCKBUILD=1
                       # echo "Set mock build to $MOCKBUILD"
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
fi

VERSION=$(echo "${NEWARGS}" | tr -t '/' ' ' | awk '{print $2}')

#echo "MODE is == $MODE"
#echo "MOCKBUILD is == $MOCKBUILD"
#echo "VERSION is == $VERSION"

case "${MODE}" in
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
              install_network
           ;;
           edk2)
              install_edk2
           ;;
           iso)
              install_prebuilt_iso
              install_edk2_zip
           ;;
           *)
           echo "  Invalid argument: $MODE" >&2
           echo "  Try: \"$0 -h\"" >&2
           exit 1
           ;;
esac
