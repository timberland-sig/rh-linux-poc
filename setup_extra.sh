#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

. $DIR/global_vars.sh

MODES="iso|copr|rpms|artif|mock|build"
MODE=""
RPM_VERSIONS="fedora-36|fedora-37|fedora-42|centos-stream-9|opensuse-tumbleweed"
RH_VERSIONS="fedora-36|fedora-37|fedora-42|centos-stream-9"
MOCK_VERSION=fedora-36-x86_64
MOCKBUILD=0

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
        echo "                : Download a release ISO and a prebuilt Timberland SIG EDK2"
        echo "                : - ISOs appear in 'ISO' directory"
        echo ""
        echo " Examples: "
        echo "  Install qemu and configure hypervisor networks"
        echo "       ./${0##*/} virt "
        echo "       ./${0##*/} net "
        echo "  Configure hypervisor and install prebuilt bits"
        echo "       ./${0##*/} prebuilt fedora-39 "
        echo "  Configure user/dev environment, clone all repositories and build all bits"
        echo "       ./${0##*/} -m build fedora-37"
        echo "  Build an ISO with copr rpms and local edk2 artifacts"
        echo "       ./${0##*/} -m iso fedora-36 "
        echo ""
        exit 1
}

check_version_rh() {
    if [ -z "${VERSION}" ]; then
        echo "  Invalid argument: ${NEWARGS}" >&2
        echo "  use: \"$0 $MODE <$RH_VERSIONS>\"" >&2
		echo " Bar"
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

case "${MODE}" in
    iso)
        check_version_iso
        install_devel
        build_copr_iso $VERSION
    ;;
    copr)
        #check_version_rh
        create_copr_project
        build_libnvme_rpms copr $COPR_PROJECT
        build_dracut_rpms copr $COPR_PROJECT
        build_nvme_rpms copr $COPR_PROJECT
    ;;
    rpms)
        build_libnvme_rpms rpm
        build_dracut_rpms rpm
        build_nvme_rpms rpm
    ;;
    artif*)
        install_artifacts_zip
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
    build)
        check_version_iso
        install_devel
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
