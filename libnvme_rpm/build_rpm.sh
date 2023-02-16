#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

VERSION=1.3
RELEASE=1

rm -f libnvme-${VERSION}.tar.gz
pushd libnvme 
make purge
make
git archive --format=tar HEAD > libnvme-${VERSION}.tar
mv libnvme-${VERSION}.tar ../
popd

tar rf libnvme-${VERSION}.tar libnvme.spec
gzip -f -9 libnvme-${VERSION}.tar

# 
# https://stackoverflow.com/questions/23965958/how-to-change-rpmbuild-default-directory-form-root-rpmbuild-directory-to-other
#

rm -rf rmpbuild
mkdir -p rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
rpmbuild -ta --define "_topdir `pwd`/rpmbuild" -v  libnvme-${VERSION}.tar.gz

