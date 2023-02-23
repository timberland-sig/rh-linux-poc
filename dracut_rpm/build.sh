#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../rpm_lib.sh

VERSION=059
RELEASE=1
MODE=srpm

if [ $# -gt 0 ]; then
  MODE=$1
fi

build_dist() {
    rm -rf dracut-${VERSION} dracut-${VERSION}.tar.xz
    pushd dracut
    make clean
    make dist
    cp dracut-${VERSION}.tar.xz ../
    make clean
    popd
    xz -d -v dracut-${VERSION}.tar.xz
    tar -xf dracut-${VERSION}.tar
    cp dracut.spec dracut-${VERSION}
    rm dracut-${VERSION}.tar
    tar -cf dracut-${VERSION}.tar dracut-${VERSION}
    xz -9 dracut-${VERSION}.tar
    rm -rf dracut-${VERSION}
}

prep_rpm() {
    rm -rf rmpbuild
    mkdir -p rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
}

build_rpm () {
    rpmbuild -ta --define "_topdir `pwd`/rpmbuild" -v dracut-${VERSION}.tar.xz
}

build_srpm () {
    rpmbuild -ts --define "_topdir `pwd`/rpmbuild" -v dracut-${VERSION}.tar.xz
}

pushd $DIR

case "${MODE}" in
           srpm)
             build_dist
             prep_rpm
             build_srpm
           ;;
           rpm)
             build_dist
             prep_rpm
             build_rpm
           ;;
           copr)
             build_dist
             prep_rpm
             build_srpm
             build_copr_pkg "rpmbuild/SRPMS/dracut-*.src.rpm"
           ;;
           mock)
             build_dist
             prep_rpm
             build_srpm
             RPM="$(ls rpmbuild/SRPMS/dracut-*.src.rpm)"
             mock -r fedora-36-x86_64 --arch=x86_64 --no-clean --resultdir $PWD/mock_dracut $RPM
           ;;
           *)
           echo " Invalid argument: $MODE" >&2
           display_rpm_help
           popd
           exit 1
           ;;
esac

rm -f dracut-${VERSION}.tar.xz

popd
