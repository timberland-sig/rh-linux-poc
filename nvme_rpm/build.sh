#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../rpm_lib.sh

VERSION=2.3
RELEASE=1
MODE=blank
COPR_PROJECT=blank

check_args $# $1 $2

build_dist() {
    rm -f nvme-cli-${VERSION}.tar.gz
    cp nvme-cli.spec nvme-cli
    pushd nvme-cli
    make purge
    git archive --output ../nvme-cli-${VERSION}.tar --format=tar --add-file nvme-cli.spec HEAD
    rm nvme-cli.spec
    popd
    gzip -f -9 nvme-cli-${VERSION}.tar
}

prep_rpm() {
    rm -rf rmpbuild
    mkdir -p rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
}

build_rpm () {
    rpmbuild -ta --define "_topdir `pwd`/rpmbuild" -v  nvme-cli-${VERSION}.tar.gz
}

build_srpm () {
    rpmbuild -ts --define "_topdir `pwd`/rpmbuild" -v  nvme-cli-${VERSION}.tar.gz
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
             RPM="$(ls rpmbuild/SRPMS/nvme-cli-*.src.rpm)"
             build_copr_pkg $COPR_PROJECT "$RPM"
           ;;
           mock)
             build_dist
             prep_rpm
             build_srpm
             RPM="$(ls rpmbuild/SRPMS/nvme-cli-*.src.rpm)"
             mock -r fedora-36-x86_64 --arch=x86_64 --no=clean --resultdir $PWD/mock_nvme-cli $RPM
           ;;
           *)
           echo " Invalid argument: $MODE" >&2
           display_rpm_help
           popd
           exit 1
           ;;
esac

rm -f nvme-cli-${VERSION}.tar.gz

popd
