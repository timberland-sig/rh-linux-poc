#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

DIR="$(dirname -- "$(realpath -- "$0")")"
. $DIR/../rpm_lib.sh

VERSION=2.3
RELEASE=1

MODE=srpm

if [ $# -gt 0 ]; then
  MODE=$1
fi

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
             build_copr_pkg "rpmbuild/SRPMS/nvme-cli-*.src.rpm"
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
