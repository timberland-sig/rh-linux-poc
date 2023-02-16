#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

VERSION=059
RELEASE=1

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

# 
# https://stackoverflow.com/questions/23965958/how-to-change-rpmbuild-default-directory-form-root-rpmbuild-directory-to-other
#

rm -rf rmpbuild
mkdir -p rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
rpmbuild -ta --define "_topdir `pwd`/rpmbuild" -v dracut-${VERSION}.tar.xz 

