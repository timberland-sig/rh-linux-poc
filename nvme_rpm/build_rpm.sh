#!/bin/bash
# SPDX-License-Identifier: GPL-3.0+
# Copyright (C) 2023 John Meneghini <jmeneghi@redhat.com> All rights reserved.

VERSION=2.3
RELEASE=1

rm -f nvme-cli-${VERSION}.tar.gz
pushd nvme-cli
make purge
make
git archive --format=tar HEAD > nvme-cli-${VERSION}.tar
mv nvme-cli-${VERSION}.tar ../
popd

tar rf nvme-cli-${VERSION}.tar nvme-cli.spec
gzip -f -9 nvme-cli-${VERSION}.tar

rm -rf rmpbuild
mkdir -p rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
rpmbuild -ta --define "_topdir `pwd`/rpmbuild" -v  nvme-cli-${VERSION}.tar.gz

