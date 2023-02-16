#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#echo "DIR = $DIR"

# Configuraiton
NOOP=0
MODES="all|user|pkgs|net|fedora|centos|edk2|dracut|nvme|virt|fio|cp|nvmet|blktest"
MODE="user"

display_help() {
        echo
        echo " Usage: ${0##*/} [-h] [-m <$MODES>]"
        echo "  -h help "
		echo "  -m all      : run all modules in order "
		echo "  -m user     : setup basic user environment (default)"
		echo "  -m net      : configure bridged network environment "
		echo "  -m pkgs     : install all pkgs for host build environment "
		echo "  -m virt     : install qemu-kvm environment "
		echo "  -m fedora   : download Fedora37 iso in ~/ISOs "
		echo "  -m centos   : download Centos9 iso in ~/ISOs "
		echo "  -m edk2     : setup git repository in ~/timberland/edk2  "
		echo "  -m nvme     : setup git reposigory in ~/timberland/nvme-cli "
		echo "  -m dracut   : setup git reposigory in ~/timberland/dracut "
        echo ""
        echo " Examples:"
        echo "       ${0##*/} "
        echo "       ${0##*/} -m user "
        echo "       ${0##*/} -m pkgs "
        echo "       ${0##*/} -m virt "
        echo "       ${0##*/} -m net "
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

git submodule update --init --recursive

}

install_network() {

	echo " : setup bridged network environment"

	nmcli dev show br0
	if [ $? -ne 0 ]; then
		netdev=""
		nmcli dev status
		echo ""
		read -r -p "enter name of default network managment device: " netdev

		if [ -z netdev ]; then
			exit 1
		fi

		nmcli dev show $netdev

		if [ $? -ne 0 ]; then 
			exit 1
	    fi

		mac=$(nmcli -t -f general.hwaddr -e yes dev show $netdev | sed 's/^general.hwaddr://')
		sudo nmcli con down $netdev 
		sudo nmcli con add type bridge ifname br0 autoconnect yes stp off ethernet.cloned-mac-address $mac
		sudo nmcli con add type bridge-slave ifname $netdev master br0
		sudo nmcli con up bridge-br0
		ip -h -c -o -br address show br0
	fi

	nmcli dev show virbr1
	if [ $? -ne 0 ]; then
		sudo nmcli conn add type bridge ifname virbr1 con-name virbr1 stp yes ipv4.addresses 192.168.101.1/24 ipv4.method manual ipv6.method shared
		ip -h -c -o -br address show virbr1 
	fi

	nmcli dev show virbr2
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
#if [ -f /etc/redhat-release ]; then
#    sudo dnf install -y --skip-broken meson cmake dbus-devel libuuid libuuid-devel libuuid-debuginfo json-c-devel json-c-debuginfo json-c json-c-doc
#    sudo dnf install -y --skip-broken libhugetlbfs libhugetlbfs-devel libhugetlbfs-lib clang openssl openssl-devel
#fi
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
if [ -f /etc/redhat-release ]; then
	sudo dnf -y --skip-broken groupinstall "Development tools"
    sudo dnf -y --skip-broken install python3-devel libuuid-devel acpica-tools binutils gcc gcc-c++ git nasm
fi
pushd $HOME
if [ ! -d timberland/edk2 ]; then
    mkdir -p timberland/edk2
    pushd timberland/edk2
	git clone -b timberland_1.0_final git@github.com:timberland-sig/edk2-private.git
    pushd edk2-private
    git config url."ssh://git@github.com/timberland-sig".insteadOf https://github.com/timberland-sig
    git submodule update --init --recursive
    make -C BaseTools
    source edksetup.sh
    build -t GCC5 -a X64 -p OvmfPkg/OvmfPkgX64.dsc
    mkdir -p $HOME/OVMF
    cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_CODE.fd $HOME/OVMF
    cp Build/OvmfX64/DEBUG_GCC5/FV/OVMF_VARS.fd $HOME/OVMF
	cp Build/OvmfX64/DEBUG_GCC5/X64/NvmeOfCli.efi $HOME/OVMF
	popd
	popd
fi
popd
}

install_pkgs() {
if [ -f /etc/redhat-release ]; then
	sudo dnf groupinstall -y "Development tools"
    sudo dnf install -y --skip-broken asciidoc audit-libs-devel binutils-devel elfutils-devel java-devel kabi-dw libcap-devel libcap-ng-devel libmnl-devel llvm ncurses-devel newt-devel nss-tools numactl-devel pciutils-devel perl perl-generators pesign python3-devel python3-docutils xmlto rpm-build yum-utils sg3_utils dwarves libbabeltrace-devel libbpf-devel openssl-devel net-tools wget bison acpica-tools binutils gcc gcc-c++ git meson cmake dbus-devel libuuid libuuid-devel libuuid-debuginfo json-c-devel json-c-debuginfo json-c json-c-doc libhugetlbfs libhugetlbfs-devel libhugetlbfs-lib clang openssl kmod-devel systemd-devel
fi
}

install_virt() {
if [ -f /etc/redhat-release ];then
    sudo dnf install -y --skip-broken qemu-kvm
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
           all)
              install_user
              install_pkgs
              install_network
              install_virt
              install_fedora_iso
              install_edk2
              echo ""
              echo " Ready to run install.sh"
              echo ""
           ;;
           *)
           echo "  Invalid argument: $MODE" >&2
           echo "  Try: \"$0 -h\"" >&2
           exit 1
           ;;
esac
