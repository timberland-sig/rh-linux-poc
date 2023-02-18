#!/bin/bash
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
	rm -f dracut-${VERSION}.tar.xz
	pushd dracut
	make clean
	make dist
	cp dracut-${VERSION}.tar.xz ../
	make clean
	popd
	xz -d -v dracut-${VERSION}.tar.xz
	tar rf dracut-${VERSION}.tar dracut.spec
	xz -9 dracut-${VERSION}.tar
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
