#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#echo "DIR = $DIR"

# Configuraiton
NOOP=0
MODES="build|user|pkgs|net|rpms|fedora|centos|edk2|dracut|nvme|virt|fio|cp|nvmet|blktest"
MODE="user"

display_help() {
        echo
        echo " Usage: ${0##*/} [-h] [-m <$MODES>]"
        echo "  -h help "
		echo "  -m user     : setup basic user environment (default)"
		echo "  -m pkgs     : install all pkgs for host build environment "
		echo "  -m build    : run all modules to build timberlan-sig artifacts  "
		echo "  -m edk2     : build timberland-sig repository in timberland_edk2  "
		echo "              : - install build artifacts in OVMF directory  "
		echo "  -m rpms     : build rpms for dracut, libnvme and nvme-cli "
		echo "              : - install rpm artifacts in {dir}_rpm/rpmbuild/..."
		echo "  -m net      : configure bridged network environment "
		echo "  -m virt     : install qemu-kvm environment "
		echo "  -m fedora   : download Fedora37 iso in ~/ISOs "
		echo "  -m centos   : download Centos9 iso in ~/ISOs "
		echo "  -m nvme     : build timberland-sig repository in ~/timberland/nvme-cli "
		echo "  -m dracut   : build timberland-sig repository in ~/timberland/dracut "
        echo ""
        echo " Examples:"
        echo "       ${0##*/} "
        echo "       ${0##*/} -m user "
        echo "       ${0##*/} -m pkgs "
        echo "       ${0##*/} -m build "
        echo "       ${0##*/} -m net "
        echo "       ${0##*/} -m virt "
        echo "       ${0##*/} -h "
        echo ""
        exit 1
}

install_user() {

echo " : Installing user environment"

if [ -f /etc/redhat-release ]; then
    sudo dnf install -y --skip-broken vim git tar gpg wget ethtool pciutils net-tools
fi

mkdir -p $HOME/ISO
mkdir -p $HOME/timberland
mkdir -p $HOME/repos

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
		read -r -p "enter name of default network managment device: " netdev

		if [ -z netdev ]; then
			exit 1
		fi

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

	nmcli dev show virbr1 &>/dev/null
	if [ $? -ne 0 ]; then
		sudo nmcli conn add type bridge ifname virbr1 con-name virbr1 stp yes ipv4.addresses 192.168.101.1/24 ipv4.method manual ipv6.method shared
		ip -h -c -o -br address show virbr1
	fi

	nmcli dev show virbr2 &>/dev/null
	if [ $? -ne 0 ]; then
		sudo nmcli conn add ifname virbr2 type bridge con-name virbr2 stp yes ipv4.addresses 192.168.102.1/24 ipv4.method manual ipv6.method shared
		ip -h -c -o -br address show virbr2
	fi
}

install_nvmetcli() {
pushd $HOME
if [ ! -d repos/nvmetcli ]; then
    mkdir -p repos/nvmetcli
    pushd repos/nvmetcli
    git clone git://git.infradead.org/users/hch/nvmetcli.git
    popd
fi
popd
}

build_dracut_rpms() {
if [ ! -d $DIR/dracut_rpm ]; then
	echo "$DIR/dracut_rpm not found!"
	exit 1
else
	$DIR/dracut_rpm/build.sh
fi
}

build_nvme_rpms() {
if [ ! -d $DIR/nvme_rpm ]; then
	echo "$DIR/nvme_rpm not found!"
	exit 1
else
	$DIR/nvme_rpm/build.sh
fi
}

build_libnvme_rpms() {
if [ ! -d $DIR/libnvme_rpm ]; then
	echo "$DIR/libnvme_rpm not found!"
	exit 1
else
	$DIR/libnvme_rpm/bulid.sh
fi
}

install_dracut() {
pushd $HOME
if [ ! -d timberland/dracut ]; then
    mkdir -p timberland/dracut
    pushd timberland/dracut
    git clone git@github.com:timberland-sig/dracut
    pushd dracut
    git remote add upstream git@github.com:dracutdevs/dracut.git
	popd
	popd
fi
popd
}

install_nvme() {
	if [ ! -f .pkgs ]; then
		sudo dnf install -y meson cmake dbus-devel libuuid libuuid-devel libuuid-debuginfo json-c-devel json-c-debuginfo json-c json-c-doc
		sudo dnf install -y libhugetlbfs libhugetlbfs-devel libhugetlbfs-lib clang openssl openssl-devel
	fi
	pushd $HOME
	if [ ! -d timberland/nvme-cli ]; then
		mkdir -p timberland/nvme-cli
		pushd timberland/nvme-cli
		git clone git@github.com:timberland-sig/nvme-cli
		pushd nvme-cli
		git remote add upstream git@github.com:linux-nvme/nvme-cli.git
		make nvme
		popd
		popd
	fi
	popd
}

install_edk2() {
	pushd $DIR
	if [ ! -f .edk2pkgs ]; then
		sudo dnf -y --skip-broken groupinstall "Development tools"
		sudo dnf -y --skip-broken install python3-devel libuuid-devel acpica-tools binutils gcc gcc-c++ git nasm
		touch .edk2pkgs
	fi
	if [ ! -d timberland_edk2 ]; then
		mkdir -p timberland_edk2
		pushd timberland_edk2
		git clone -b timberland_1.0_final git@github.com:timberland-sig/edk2.git
		pushd edk2
		git config url."ssh://git@github.com/timberland-sig".insteadOf https://github.com/timberland-sig
		git submodule update --init --recursive
		popd
		popd
	fi
	pushd timberland_edk2
	pushd edk2
	make -C BaseTools clean
	rm -rf Build
	make -C BaseTools
	source edksetup.sh
	build -t GCC5 -a X64 -p OvmfPkg/OvmfPkgX64.dsc
	rm -f  $DIR/OVMF/{OVMF_CODE.fd, OVMF_VARS.fd, NvmeOfCli.efi}
	cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd $DIR/OVMF
	cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd $DIR/OVMF
	cp Build/OvmfX64/DEBUG_GCC5/X64/NvmeOfCli.efi $DIR/OVMF
	popd
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
			json-c-devel json-c json-c-doc clang openssl kmod-devel \
			systemd-devel copr-cli mock

		sudo usermod -a -G mock $USER
		touch .pkgs
	else
		echo "Nothing to do"
	fi
	popd
}

install_virt() {
if [ -f /etc/redhat-release ];then
    sudo dnf install -y qemu-kvm
	sudo echo "allow all" > /etc/qemu/bridge.conf
	sudo chmod 4755 /usr/libexec/qemu-bridge-helper
fi
}

install_cockpit() {
if [ -f /etc/redhat-release ]; then
    HOST=`hostname`
    sudo dnf install -y --skip-broken cockpit cockpit-machines
	sudo systemctl enable --now cockpit.socket
	echo ""
	echo "Access the web console by entering the https://$HOST:9090 address in your browser."
	echo ""
fi
}

install_fio() {
if [ -f /etc/redhat-release ]; then
    sudo dnf install -y --skip-broken libaio libaio-devel
fi
pushd $HOME
if [ ! -d repos/fio ]; then
    mkdir -p repos/fio
    pushd repos/fio
    git clone git@github.com:axboe/fio.git
    popd
fi
popd
}

install_blktest() {
if [ -f /etc/redhat-release ]; then
    sudo dnf install -y --skip-broken ShellCheck blktrace blktrace-debuginfo libpmem*
	hash fio 2>/dev/null || { echo >&2 "fio required but not installed."; install_fio; }
	hash nvme 2>/dev/null || { echo >&2 "nvme required but not installed."; install_nvme; }
	hash nvmetcli 2>/dev/null || { echo >&2 "nvme required but not installed."; install_nvmet; }
fi
pushd $HOME
if [ ! -d repos/tests ]; then
    mkdir -p repos/tests
    pushd repos/tests
    git clone git@github.com:osandov/blktests.git
    popd
fi
popd
}

install_centos_iso() {
pushd $HOME
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

install_fedora_iso() {
pushd $HOME
if [ ! -d ISO ]; then
    mkdir -p ISO
fi

if [ ! -f ISO/Fedora-Server-dvd-x86_64-37-1.7.iso ]; then
    pushd ISO
	wget https://download.fedoraproject.org/pub/fedora/linux/releases/37/Server/x86_64/iso/Fedora-Server-dvd-x86_64-37-1.7.iso
	popd
fi
popd
}

while getopts "m:h" opt; do
        case "${opt}" in
                h)
                        display_help >&2
                        exit 0
                ;;
			    m)
                        MODE=$OPTARG
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
           cp)
              install_cockpit
           ;;
           nvme)
              install_nvme
           ;;
           rpms)
              build_dracut_rpms
			  build_libnvme_rpms
			  build_nvme_rpms
           ;;
           dracut)
              install_dracut
           ;;
           nvmet)
              install_nvmet
           ;;
           fio)
              install_fio
           ;;
           edk2)
              install_edk2
           ;;
           fedora)
              install_fedora_iso
           ;;
           centos)
              install_centos_iso
           ;;
           blktest)
              install_blktest
           ;;
           build)
              install_user
              install_pkgs
              build_dracut_rpms
			  build_libnvme_rpms
			  build_nvme_rpms
              install_edk2
              install_fedora_iso
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
