#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#echo "DIR = $DIR"
. $DIR/global_vars.sh

# Configuraiton
NOOP=0
MODES="build|user|pkgs|net|virt|mock|copr|edk2|iso|prebuilt"
MODE="user"
MOCKBUILD=0
ALL_VERSIONS="fedora-36|fedora-37|fedora-42|centos-stream-9|opensuse-tumbleweed"
RPM_VERSIONS="fedora-36|fedora-37|fedora-42|centos-stream-9|opensuse-tumbleweed"
RH_VERSIONS="fedora-36|fedora-37|fedora-42|centos-stream-9"
MOCK_VERSION=fedora-36-x86_64

display_help() {
        echo
        echo " Usage: ${0##*/} [-h] [-m ] <$MODES> [$ALL_VERSIONS]"
        echo
        echo "  -h            : display this help"
        echo "  -m            : use mock to build things"
        echo ""
        echo "  user          : setup basic user environment (default)"
        echo "  pkgs          : install all pkgs needed for host build environment "
        echo "  virt          : install qemu-kvm environment "
        echo "  edk2          : create and build the timberland-sig edk2 repository in the edk2 directory "
        echo "                : - install build artifacts in OVMF directory  "
        echo "  copr          : create copr project $COPR_PROJECT and upload all rpms "
        echo "                : - results at: https://copr.fedorainfracloud.org/coprs/"
        echo "  net           : configure network environment "
        echo "                : - script prompts for \"bridged\" primary interface."
        echo "                :   Enter \"local\" to skip primary interace reconfiguration."
        echo "  artifacts     : install prebuilt EDK2 artifacts"
        echo "                :   Download artifacts.zip in \"artifacts\" directory first. "
        echo "  mock  < $ALL_VERSIONS > "
        echo "                : mock build of all rpms "
        echo "  iso   < $ISO_VERSIONS > "
        echo "                : build bootable iso image with timberland-sig artifacts"
        echo "                : - results appear in 'lorax/results' directory"
        echo "  build < $ISO_VERSIONS > "
        echo "                : install packages, build edk2, create copr repository, and build iso"
        echo "                : - results appear in 'lorax/results' directory"
        echo ""
        echo "  prebuilt < $ISO_VERSIONS > "
        echo "                : Download Fedora release ISO and install prebuilt Timberland SIG packages"
        echo "                : - ISOs appear in 'ISO' directory"
        echo "                : - Prebuilt RPMs come from 'https://copr.fedorainfracloud.org/coprs/johnmeneghini/$COPR_PROJECT/'"
        echo ""
        echo " Examples: "
        echo "  Install qemu and configure hypervisor networks"
        echo "       ./${0##*/} virt "
        echo "       ./${0##*/} net "
        echo "  Configure hypervisor and install prebuilt bits"
        echo "       ./${0##*/} prebuilt fedora-36 "
        echo "  Configure user/dev environment, clone all repositories and build all bits"
        echo "       ./${0##*/} -m build fedora-37"
        echo "  Build an ISO with copr rpms and local edk2 artifacts"
        echo "       ./${0##*/} -m iso fedora-36 "
        echo ""
        exit 1
}

install_user() {

    echo " : Installing user environment"

    if [ ! -f .usr ]; then

        sudo dnf install -y --skip-broken vim git tar gpg wget ethtool pciutils net-tools copr-cli nvme-cli

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

        touch .usr
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

build_dracut_rpms() {
    if [ ! -d $DIR/dracut_rpm ]; then
        echo "$DIR/dracut_rpm not found!"
        exit 1
    else
        $DIR/dracut_rpm/build.sh $1 $2
    fi
}

build_nvme_rpms() {
    if [ ! -d $DIR/nvme_rpm ]; then
        echo "$DIR/nvme_rpm not found!"
        exit 1
    else
        $DIR/nvme_rpm/build.sh $1 $2
    fi
}

build_libnvme_rpms() {
    if [ ! -d $DIR/libnvme_rpm ]; then
        echo "$DIR/libnvme_rpm not found!"
        exit 1
    else
        $DIR/libnvme_rpm/build.sh $1 $2
    fi
}

create_copr_project() {
    FOO="$(copr-cli list | grep "Name..$COPR_PROJECT")"
    if [ -z "$FOO" ]; then
        echo "Create copr $COPR_PROJECT project."
        copr-cli create --chroot fedora-42-x86_64 --chroot fedora-37-x86_64 --chroot fedora-36-x86_64 \
        --description "Timberland-sig NVMe/TCP Boot support" \
        --instructions "File bugs and propose patches at https://github.com/timberland-sig" $COPR_PROJECT
    fi
}

install_edk2() {
    pushd $DIR
    if [ ! -f .edk2pkgs ]; then
        sudo dnf -y groupinstall "Development tools"
        sudo dnf -y install python3-devel libuuid-devel acpica-tools binutils gcc gcc-c++ git nasm
        touch .edk2pkgs
    fi
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

install_pkgs() {
    pushd $DIR
    if [ ! -f .pkgs ]; then
        sudo dnf groupinstall -y "Development tools"
        sudo dnf install -y asciidoc audit-libs-devel binutils-devel elfutils-devel java-devel kabi-dw libcap-devel \
            libcap-ng-devel libmnl-devel llvm ncurses-devel newt-devel nss-tools numactl-devel pciutils-devel perl perl-generators \
            pesign python3-devel python3-docutils xmlto rpm-build yum-utils sg3_utils dwarves libbabeltrace-devel libbpf-devel openssl-devel \
            net-tools wget bison acpica-tools binutils gcc gcc-c++ git meson cmake dbus-devel libuuid libuuid-devel \
            json-c-devel json-c json-c-doc clang openssl kmod-devel zip unzip\
            python3-sphinx python3-sphinx_rtd_theme swig \
            systemd-devel mock lorax
        sudo usermod -a -G mock $USER
        touch .pkgs
    else
        echo "Nothing to do"
    fi
    popd
}

build_mock_iso() {

    echo "mock build"

    case "$1" in
      fedora-*)
          rm -rf lorax_results
          mock -r $MOCK_VERSION --install lorax
          mock -r $MOCK_VERSION --arch=x86_64 --enable-network --isolation=simple --resultdir $DIR/mock_result --chroot "$2"
          status=$?
          ;;
      *)
          echo "$1 is not supported"
          status=1
          ;;
    esac

    if [[ $status -eq 0 ]]; then
      set -e
      sudo cp -r /var/lib/mock/$MOCK_VERSION/root/lorax_results $PWD
      sudo chown -R $USER lorax_results
      sudo chgrp -R $USER lorax_results
    else
      echo "mock build failed!"
    fi
}

build_direct_iso() {

    echo "direct build"

    ENFORCE=`getenforce`

    if [[ $ENFORCE == *"Enforcing" ]]; then sudo setenforce 0; fi

    pushd $DIR
    rm -rf lorax lorax_results
    mkdir -p lorax

    pushd lorax

    sudo $1

    popd

    if [[ $ENFORCE == *"Enforcing" ]]; then sudo setenforce 1; fi

    sudo chown -R $USER lorax
    sudo chgrp -R $USER lorax
    mv lorax/lorax_results .

    popd
}

mock_iso() {

    exit 1

    case "$1" in
        fedora-36)
        LORAX_BUILD="lorax -p Fedora -v 36 -r 36 --nomacboot --volid Fedora-S-dvd-x86_64-f36 -s https://dl.fedoraproject.org/pub/fedora/linux/releases/36/Everything/x86_64/os/ lorax_results"
            ;;
        fedora-37)
        LORAX_BUILD="lorax -p Fedora -v 37 -r 37 --nomacboot --volid Fedora-S-dvd-x86_64-f37 -s https://dl.fedoraproject.org/pub/fedora/linux/releases/37/Everything/x86_64/os/ lorax_results"
            ;;
        centos-stream-9)
            echo "$1 is not supported"
            ;;
        *)
            ;;
    esac

#    echo "LORAX_BUILD = \"$LORAX_BUILD\""

    build_mock_iso $1 "$LORAX_BUILD"

}

build_copr_iso() {

    copr-cli list | grep "$COPR_PROJECT\/$1"
    if [ $? -ne 0 ]; then
        echo "No repository for $1 found"
        copr-cli list
        exit 1
    else
        REPO=$(copr-cli list | grep "$COPR_PROJECT\/$1" | tr -d '()' | awk '{print $2}')
    fi

    case "$1" in
        fedora-36)
        LORAX_BUILD="lorax -p Fedora -v 36 -r 36 --nomacboot --volid Fedora-S-dvd-x86_64-f36 -s https://dl.fedoraproject.org/pub/fedora/linux/releases/36/Everything/x86_64/os/ -s $REPO lorax_results"
            ;;
        fedora-37)
        LORAX_BUILD="lorax -p Fedora -v 37 -r 37 --nomacboot --volid Fedora-S-dvd-x86_64-f37 -s https://dl.fedoraproject.org/pub/fedora/linux/releases/37/Everything/x86_64/os/ -s $REPO lorax_results"
            ;;
        fedora-42)
        LORAX_BUILD="lorax -p Fedora -v 42 -r 42 --nomacboot --volid Fedora-S-dvd-x86_64-f42 -s https://dl.fedoraproject.org/pub/fedora/linux/releases/42/Everything/x86_64/os/ -s $REPO lorax_results"
            ;;
            *)
              echo "$1 is not supported"
              status=1
            ;;
    esac

    echo "LORAX_BUILD = \"$LORAX_BUILD\""

    if [[ $MOCKBUILD -eq 1 ]]; then
        mock -r $MOCK_VERSION --init
        build_mock_iso $1 "$LORAX_BUILD"
    else
        build_direct_iso "$LORAX_BUILD"
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

install_centos_iso() {
    pushd $DIR
    if [ ! -d ISO ]; then
        mkdir -p ISO
    fi

    if [ ! -f ISO/CentOS-Stream-9-latest-x86_64-dvd1.iso ]; then
        pushd ISO
        wget https://download.cf.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso
        popd
    fi
    popd
}

install_edk2_zip() {
    pushd $DIR

    if [ ! -d ISO ]; then
        mkdir -p ISO
    fi

    if [ ! -f ISO/$OVMF_ZIP ]; then
        pushd ISO
        wget $OVMF_URL/$OVMF_ZIP
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

install_artifacts_zip() {
    pushd $DIR

	if [ ! -d ISO ]; then
        mkdir -p ISO
    fi

    if [ ! -f artifacts/artifact.zip ]; then
        echo "file artifact.zip not found!"
		exit 1
    fi

    pushd artifacts
	unzip artifact.zip

    if [ ! -f timberland-ovmf.zip ]; then
        echo "file timberland-ovmf.zip not found!"
		exit 1
	fi

	unzip timberland-ovmf.zip

    if [ ! -f OVMF_CODE.fd ]; then
        echo "file OVMF_CODE.fd not found!"
        exit 1
    fi

	popd

    rm -f  host-vm/OVMF_CODE.fd
    rm -f  host-vm/vm_vars.fd
    rm -f  host-vm/eficonfig/NvmeOfCli.efi
    rm -f  host-vm/eficonfig/VConfig.efi
    cp -fv artifacts/OVMF_CODE.fd host-vm/OVMF_CODE.fd
    cp -fv artifacts/OVMF_VARS.fd host-vm/vm_vars.fd
    cp -fv artifacts/OVMF_VARS.fd ISO/OVMF_VARS.fd
    cp -fv artifacts/NvmeOfCli.efi host-vm/eficonfig/NvmeOfCli.efi
    cp -fv artifacts/VConfig.efi host-vm/eficonfig/VConfig.efi

	popd
}

install_prebuilt_iso() {
    pushd $DIR
    if [ ! -f .pkgs2 ]; then
        sudo dnf -y --skip-broken install vim tar wget net-tools zip unzip
        touch .pkgs2
    fi
    if [ ! -d ISO ]; then
        mkdir -p ISO
    fi
    case "${VERSION}" in
        fedora-36)
            VER=36
            ISOVERSION="$ISOVERSION_F36"
        ;;
        fedora-37)
            VER=37
            ISOVERSION="$ISOVERSION_F37"
        ;;
        fedora-42)
            VER=42
            ISOVERSION="$ISOVERSION_F42"
        ;;
        *)
            echo "  Invalid argument: $VERSION" >&2
            echo "  use: \"$0 $MODE <$ISO_VERSIONS>\"" >&2
            exit 1
        ;;
    esac

    if [ ! -f ISO/$ISOVERSION ]; then
        pushd ISO
        wget https://download.fedoraproject.org/pub/fedora/linux/releases/$VER/Everything/x86_64/iso/$ISOVERSION
        popd
    fi
    popd
}

check_version_rpm() {
    if [ -z "${VERSION}" ]; then
        echo "  Invalid argument: ${NEWARGS}" >&2
        echo "  use: \"$0 $MODE <$RPM_VERSIONS>\"" >&2
        echo "  Try: \"$0 -h\"" >&2
        exit 1
    fi
    case "${VERSION}" in
        fedora-36)
            MOCK_VERSION=fedora-36-x86_64
        ;;
        fedora-37)
            MOCK_VERSION=fedora-37-x86_64
        ;;
        fedora-42)
            MOCK_VERSION=fedora-42-x86_64
        ;;
        centos-stream-9)
            MOCK_VERSION="centos-stream+epel-9-x86_64"
        ;;
        opensuse-tumbleweed)
            MOCK_VERSION=opensuse-tumbleweed-x86_64
        ;;
        *)
            echo "  Invalid argument: $VERSION" >&2
            echo "  use: \"$0 $MODE <$RPM_VERSIONS>\"" >&2
            exit 1
        ;;
    esac
}

check_version_rh() {
    if [ -z "${VERSION}" ]; then
        echo "  Invalid argument: ${NEWARGS}" >&2
        echo "  use: \"$0 $MODE <$RH_VERSIONS>\"" >&2
        echo "  Try: \"$0 -h\"" >&2
        exit 1
    fi
    case "${VERSION}" in
        fedora-36)
            MOCK_VERSION=fedora-36-x86_64
        ;;
        fedora-37)
            MOCK_VERSION=fedora-37-x86_64
        ;;
        fedora-42)
            MOCK_VERSION=fedora-42-x86_64
        ;;
        centos-stream-9)
            MOCK_VERSION="centos-stream+epel-9-x86_64"
        ;;
        *)
            echo "  Invalid argument: $VERSION" >&2
            echo "  use: \"$0 $MODE <$RH_VERSIONS>\"" >&2
            exit 1
        ;;
    esac
}

check_version_iso() {
    if [ -z "${VERSION}" ]; then
        echo "  Invalid argument: ${NEWARGS}" >&2
        echo "  use: \"$0 $MODE <$ISO_VERSIONS>\"" >&2
        echo "  Try: \"$0 -h\"" >&2
        exit 1
    fi
    case "${VERSION}" in
        fedora-36)
            MOCK_VERSION=fedora-36-x86_64
        ;;
        fedora-37)
            MOCK_VERSION=fedora-37-x86_64
        ;;
        fedora-42)
            MOCK_VERSION=fedora-42-x86_64
        ;;
        *)
            echo "  Invalid argument: $VERSION" >&2
            echo "  use: \"$0 $MODE <$ISO_VERSIONS>\"" >&2
            exit 1
        ;;
    esac
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

case "${MODE}" in
           user)
              install_user
           ;;
           pkgs)
              install_pkgs
           ;;
           virt)
              install_virt
           ;;
           net)
              install_network
           ;;
           copr)
              #check_version_rh
              create_copr_project
              build_libnvme_rpms copr $COPR_PROJECT
              build_dracut_rpms copr $COPR_PROJECT
              build_nvme_rpms copr $COPR_PROJECT
           ;;
           mock)
              check_version_rpm
              rm -rf $DIR/mock_repo
              pushd $DIR
              build_libnvme_rpms srpm
              build_nvme_rpms srpm
              build_dracut_rpms srpm
              SRPM1="$(ls libnvme_rpm/rpmbuild/SRPMS/libnvme-*.src.rpm)"
              SRPM2="$(ls nvme_rpm/rpmbuild/SRPMS/nvme-cli-*.src.rpm)"
              SRPM3="$(ls dracut_rpm/rpmbuild/SRPMS/dracut-*.src.rpm)"
              mock -r $MOCK_VERSION --init
              mock -r $MOCK_VERSION --arch=x86_64 --no-clean --localrepo=$DIR/mock_repo --chain $SRPM1 $SRPM2 $SRPM3
              popd
           ;;
           rpms)
              build_libnvme_rpms rpm
              build_dracut_rpms rpm
              build_nvme_rpms rpm
           ;;
           edk2)
              install_edk2
           ;;
           prebuilt)
              check_version_iso
              install_prebuilt_iso
              install_edk2_zip
           ;;
           artif*)
              install_artifacts_zip
           ;;
           centos)
               exit 0
               install_centos_iso
           ;;
           iso)
              check_version_iso
              install_user
              install_pkgs
              build_copr_iso $VERSION
           ;;
           build)
              check_version_iso
              install_user
              install_pkgs
              install_edk2
              build_libnvme_rpms copr $COPR_PROJECT
              build_dracut_rpms copr $COPR_PROJECT
              build_nvme_rpms copr $COPR_PROJECT
              build_copr_iso $VERSION
              echo ""
              echo " All artifacts have been built"
              echo ""
           ;;
           *)
           echo "  Invalid argument: $MODE" >&2
           echo "  Try: \"$0 -h\"" >&2
           exit 1
           ;;
esac
