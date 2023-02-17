#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

TOP=`git rev-parse --show-toplevel`
. $TOP/rpm_lib.sh

VERSION=1.3
RELEASE=1
MODE=srpm

if [ $# -gt 0 ]; then 
  MODE=$1
fi

build_dist() {
	rm -f libnvme-${VERSION}.tar.gz
	pushd libnvme 
	make purge
	make
	git archive --format=tar HEAD > libnvme-${VERSION}.tar
	mv libnvme-${VERSION}.tar ../
	popd
	tar rf libnvme-${VERSION}.tar libnvme.spec
	gzip -f -9 libnvme-${VERSION}.tar
}

prep_rpm() {
	rm -rf rmpbuild
	mkdir -p rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
}

build_rpm () {
	rpmbuild -ta --define "_topdir `pwd`/rpmbuild" -v  libnvme-${VERSION}.tar.gz
}

build_srpm () {
	rpmbuild -ts --define "_topdir `pwd`/rpmbuild" -v  libnvme-${VERSION}.tar.gz
}

pushd $TOP/libnvme_rpm 

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

rm -f libnvme-${VERSION}.tar.gz
popd
