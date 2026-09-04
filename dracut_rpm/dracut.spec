%define dracutlibdir %{_prefix}/lib/dracut
%bcond_without doc

# We ship a .pc file but don't want to have a dep on pkg-config. We
# strip the automatically generated dep here and instead co-own the
# directory.
%global __requires_exclude pkg-config

Name: dracut
Version: 112
Release: 1%{?dist}

Summary: Initramfs generator using udev

# The entire source code is GPLv2+
# except install/* which is LGPLv2+
# except util/* which is GPLv2
License: GPL-2.0-or-later AND LGPL-2.1-or-later AND GPL-2.0-only

URL: https://github.com/timberland-sig/dracut-ng

Source0: dracut-%{version}.tar.xz

Source1: https://www.gnu.org/licenses/lgpl-2.1.txt

# Please use source-git to work with this spec file:
# HowTo: https://packit.dev/source-git/work-with-source-git
# Source-git repository: https://github.com/redhat-plumbers/dracut-fedora/

BuildRequires: bash
BuildRequires: git-core
BuildRequires: pkgconfig(libkmod) >= 23
BuildRequires: gcc

BuildRequires: pkgconfig
BuildRequires: systemd
# For dracut-install.c sd-json support
BuildRequires: systemd-devel
BuildRequires: bash-completion
BuildRequires: cargo
BuildRequires: openssl-devel

%if %{with doc}
BuildRequires: docbook-style-xsl docbook-dtds libxslt
BuildRequires: asciidoctor
%endif

Obsoletes: dracut-fips <= 047
Provides:  dracut-fips = %{version}-%{release}
Obsoletes: dracut-fips-aesni <= 047
Provides:  dracut-fips-aesni = %{version}-%{release}

Provides: bundled(crate(crosvm)) = 0.1.0

Requires: bash >= 4
Requires: coreutils
Requires: cpio
Requires: filesystem >= 2.1.0
Requires: findutils
Requires: grep
Requires: kmod
Requires: sed
# Used as default initramfs compression algorithm
Requires: zstd
# Used to handle kernel modules which are xz compressed
Requires: xz
# Not sure what this is needed for
# Requires: gzip

Recommends: memstrack
Recommends: hardlink
# Probably not needed anymore if we move zstd
# Recommends: pigz
Recommends: kpartx
Recommends: (tpm2-tools if tpm2-tss)
Requires: util-linux >= 2.21
Requires: systemd >= 219
Requires: systemd-udev >= 219
Requires: procps-ng

Requires: libkcapi-hmaccalc

%description
dracut contains tools to create bootable initramfses for the Linux
kernel. Unlike other implementations, dracut hard-codes as little
as possible into the initramfs. dracut contains various modules which
are driven by the event-based udev. Having root on MD, DM, LVM2, LUKS
is supported as well as NFS, iSCSI, NBD, FCoE with the dracut-network
package.
NOTICE: This is an expermental version of dracut
from the Timberland-sig repository. This library provides
additional support for NVMe/TCP boot with the Timberland-sig
version of libnvme and nvme-cli.

%package network
Summary: dracut modules to build a dracut initramfs with network support
Requires: %{name} = %{version}-%{release}
Requires: iputils
Requires: iproute
Requires: jq
Requires: NetworkManager >= 1.20
Suggests: NetworkManager
Obsoletes: dracut-generic < 008
Provides:  dracut-generic = %{version}-%{release}

%description network
This package requires everything which is needed to build a generic
all purpose initramfs with network support with dracut.

%package caps
Summary: dracut modules to build a dracut initramfs which drops capabilities
Requires: %{name} = %{version}-%{release}
Requires: libcap

%description caps
This package requires everything which is needed to build an
initramfs with dracut, which drops capabilities.

%package live
Summary: dracut modules to build a dracut initramfs with live image capabilities
Requires: %{name} = %{version}-%{release}
Requires: %{name}-network = %{version}-%{release}
Requires: tar coreutils bash device-mapper curl parted
%if ! 0%{?rhel}
Requires: fuse ntfs-3g
%endif

%description live
This package requires everything which is needed to build an
initramfs with dracut, with live image capabilities, like Live CDs.

%package config-generic
Summary: dracut configuration to turn off hostonly image generation
Requires: %{name} = %{version}-%{release}
Obsoletes: dracut-nohostonly < 030
Provides:  dracut-nohostonly = %{version}-%{release}

%description config-generic
This package provides the configuration to turn off the host specific initramfs
generation with dracut and generates a generic image by default.

%package config-rescue
Summary: dracut configuration to turn on rescue image generation
Requires: %{name} = %{version}-%{release}
Obsoletes: dracut < 030

%description config-rescue
This package provides the configuration to turn on the rescue initramfs
generation with dracut.

%package tools
Summary: dracut tools to build the local initramfs
Requires: %{name} = %{version}-%{release}

%description tools
This package contains tools to assemble the local initrd and host configuration.

%package squash
Summary: dracut module to build an initramfs with most files in a squashfs image
Requires: %{name} = %{version}-%{release}
Requires: squashfs-tools

%description squash
This package provides a dracut module to build an initramfs, but store most files
in a squashfs image, result in a smaller initramfs size and reduce runtime memory
usage.


%prep
%autosetup -n %{name}-%{version} -S git_am
cp %{SOURCE1} .


%build
# Makefile tries to remove of network-legacy (nonexistent) unless --enable-network-legacy
%configure  --systemdsystemunitdir=%{_unitdir} \
            --bashcompletiondir=$(pkg-config --variable=completionsdir bash-completion) \
            --libdir=%{_prefix}/lib \
            --enable-dracut-cpio \
            --enable-network-legacy \
%if %{without doc}
            --disable-documentation \
%endif
            ${NULL}


%make_build DRACUT_FULL_VERSION="%{version}-%{release}"


%install
%make_install DRACUT_FULL_VERSION="%{version}-%{release}" %{?_smp_mflags} \
     libdir=%{_prefix}/lib

echo "DRACUT_VERSION=%{version}-%{release}" > $RPM_BUILD_ROOT/%{dracutlibdir}/dracut-version.sh

# we do not support dash in the initramfs
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/10dash

# we do not support mksh in the initramfs
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/00mksh

%ifnarch s390 s390x
# remove architecture specific modules
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/68cms
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/69cio_ignore
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/73zipl
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/74dasd
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/74dasd_mod
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/74dcssblk
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/74zfcp
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/74znet
%else
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/10warpclock
%endif

# we don't want example configs
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/dracut.conf.d

# we don't ship tests
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/test
rm -fr -- $RPM_BUILD_ROOT/%{dracutlibdir}/modules.d/80test*

mkdir -p $RPM_BUILD_ROOT/boot/dracut
mkdir -p $RPM_BUILD_ROOT/var/lib/dracut/overlay
mkdir -p $RPM_BUILD_ROOT%{_localstatedir}/log
touch $RPM_BUILD_ROOT%{_localstatedir}/log/dracut.log
mkdir -p $RPM_BUILD_ROOT%{_sharedstatedir}/initramfs
mkdir -p $RPM_BUILD_ROOT%{dracutlibdir}/dracut.conf.d

install -m 0644 dracut.conf.d/fedora/01-dist.conf $RPM_BUILD_ROOT%{dracutlibdir}/dracut.conf.d/01-dist.conf
rm -f $RPM_BUILD_ROOT%{_mandir}/man?/*suse*

echo 'hostonly="no"' > $RPM_BUILD_ROOT%{dracutlibdir}/dracut.conf.d/02-generic-image.conf
echo 'dracut_rescue_image="yes"' > $RPM_BUILD_ROOT%{dracutlibdir}/dracut.conf.d/02-rescue.conf

%files
%if %{with doc}
%doc README.md AUTHORS NEWS.md
%endif
%license COPYING lgpl-2.1.txt
%{_bindir}/dracut
%{_datadir}/bash-completion/completions/dracut
%{_datadir}/bash-completion/completions/lsinitrd
%{_bindir}/lsinitrd
%dir %{dracutlibdir}
%dir %{dracutlibdir}/modules.d
%{dracutlibdir}/dracut-functions.sh
%{dracutlibdir}/dracut-functions
%{dracutlibdir}/dracut-version.sh
%{dracutlibdir}/dracut-logger.sh
%{dracutlibdir}/dracut-initramfs-restore
%{dracutlibdir}/dracut-install
%{dracutlibdir}/dracut-util
%{dracutlibdir}/skipcpio
%{dracutlibdir}/dracut-cpio
%config(noreplace) %{_sysconfdir}/dracut.conf
%{dracutlibdir}/dracut.conf.d/01-dist.conf
%dir %{_sysconfdir}/dracut.conf.d
%dir %{dracutlibdir}/dracut.conf.d
%dir %{_datadir}/pkgconfig
%{_datadir}/pkgconfig/dracut.pc

%if %{with doc}
%{_mandir}/man8/dracut.8*
%{_mandir}/man8/*service.8*
%{_mandir}/man1/lsinitrd.1*
%{_mandir}/man7/dracut.kernel.7*
%{_mandir}/man7/dracut.cmdline.7*
%{_mandir}/man7/dracut.modules.7*
%{_mandir}/man7/dracut.bootup.7*
%{_mandir}/man5/dracut.conf.5*
%endif

%{dracutlibdir}/modules.d/10bash
%{dracutlibdir}/modules.d/10systemd
%{dracutlibdir}/modules.d/10systemd-network-management
%ifnarch s390 s390x
%{dracutlibdir}/modules.d/10warpclock
%endif

%{dracutlibdir}/modules.d/11fips
%{dracutlibdir}/modules.d/11fips-crypto-policies
%{dracutlibdir}/modules.d/11systemd-ac-power
%{dracutlibdir}/modules.d/11systemd-ask-password
%{dracutlibdir}/modules.d/11systemd-battery-check
%{dracutlibdir}/modules.d/11systemd-bsod
%{dracutlibdir}/modules.d/11systemd-coredump
%{dracutlibdir}/modules.d/11systemd-creds
%{dracutlibdir}/modules.d/11systemd-hostnamed
%{dracutlibdir}/modules.d/11systemd-initrd
%{dracutlibdir}/modules.d/11systemd-integritysetup
%{dracutlibdir}/modules.d/11systemd-journald
%{dracutlibdir}/modules.d/11systemd-ldconfig
%{dracutlibdir}/modules.d/11systemd-modules-load
%{dracutlibdir}/modules.d/11systemd-pcrextend
%{dracutlibdir}/modules.d/11systemd-portabled
%{dracutlibdir}/modules.d/11systemd-pstore
%{dracutlibdir}/modules.d/11systemd-repart
%{dracutlibdir}/modules.d/11systemd-resolved
%{dracutlibdir}/modules.d/11systemd-sysctl
%{dracutlibdir}/modules.d/11systemd-sysext
%{dracutlibdir}/modules.d/11systemd-sysusers-service
%{dracutlibdir}/modules.d/11systemd-timedated
%{dracutlibdir}/modules.d/11systemd-timesyncd
%{dracutlibdir}/modules.d/11systemd-tmpfiles
%{dracutlibdir}/modules.d/11systemd-udevd
%{dracutlibdir}/modules.d/11systemd-veritysetup
%{dracutlibdir}/modules.d/13modsign
%{dracutlibdir}/modules.d/13rescue
%{dracutlibdir}/modules.d/14watchdog
%{dracutlibdir}/modules.d/14watchdog-modules
%{dracutlibdir}/modules.d/16dbus-broker
%{dracutlibdir}/modules.d/16dbus-daemon
%{dracutlibdir}/modules.d/16rngd
%{dracutlibdir}/modules.d/19dbus
%{dracutlibdir}/modules.d/20i18n
%{dracutlibdir}/modules.d/30convertfs
%{dracutlibdir}/modules.d/35network-legacy
%{dracutlibdir}/modules.d/45drm
%{dracutlibdir}/modules.d/45net-lib
%{dracutlibdir}/modules.d/45plymouth
%{dracutlibdir}/modules.d/45simpledrm
%{dracutlibdir}/modules.d/45systemd-import
%{dracutlibdir}/modules.d/45url-lib
%{dracutlibdir}/modules.d/68lvmmerge
%{dracutlibdir}/modules.d/68lvmthinpool-monitor
%{dracutlibdir}/modules.d/70bluetooth
%{dracutlibdir}/modules.d/70btrfs
%{dracutlibdir}/modules.d/70crypt
%{dracutlibdir}/modules.d/70crypt-lib
%{dracutlibdir}/modules.d/70devicetree-firmware
%{dracutlibdir}/modules.d/70dm
%{dracutlibdir}/modules.d/70dmraid
%{dracutlibdir}/modules.d/70fs-lib
%{dracutlibdir}/modules.d/70kernel-modules
%{dracutlibdir}/modules.d/70kernel-modules-export
%{dracutlibdir}/modules.d/70kernel-modules-extra
%{dracutlibdir}/modules.d/70lvm
%{dracutlibdir}/modules.d/70mdraid
%{dracutlibdir}/modules.d/70memdisk
%{dracutlibdir}/modules.d/70multipath
%{dracutlibdir}/modules.d/70numlock
%{dracutlibdir}/modules.d/70nvdimm
%{dracutlibdir}/modules.d/70overlayfs
%{dracutlibdir}/modules.d/70pcmcia
%{dracutlibdir}/modules.d/70ppcmac
%{dracutlibdir}/modules.d/70qcom-adsp
%{dracutlibdir}/modules.d/70qemu
%{dracutlibdir}/modules.d/71overlayfs-crypt
%{dracutlibdir}/modules.d/71systemd-cryptsetup
%{dracutlibdir}/modules.d/73crypt-gpg
%{dracutlibdir}/modules.d/73crypt-loop
%{dracutlibdir}/modules.d/73fido2
%{dracutlibdir}/modules.d/73pcsc
%{dracutlibdir}/modules.d/73pkcs11
%{dracutlibdir}/modules.d/73tpm2-tss
%{dracutlibdir}/modules.d/74chrony
%{dracutlibdir}/modules.d/74debug
%{dracutlibdir}/modules.d/74fstab-sys
%{dracutlibdir}/modules.d/74hwdb
%{dracutlibdir}/modules.d/74lunmask
%{dracutlibdir}/modules.d/74resume
%{dracutlibdir}/modules.d/74rootfs-block
%{dracutlibdir}/modules.d/74rootfs-block-fallback
%{dracutlibdir}/modules.d/74terminfo
%{dracutlibdir}/modules.d/74udev-rules
%{dracutlibdir}/modules.d/74virtfs
%{dracutlibdir}/modules.d/74virtiofs
%{dracutlibdir}/modules.d/75securityfs
%{dracutlibdir}/modules.d/76biosdevname
%{dracutlibdir}/modules.d/76masterkey
%{dracutlibdir}/modules.d/76systemd-emergency
%{dracutlibdir}/modules.d/77dracut-systemd
%{dracutlibdir}/modules.d/77ecryptfs
%{dracutlibdir}/modules.d/77initqueue
%{dracutlibdir}/modules.d/77integrity
%{dracutlibdir}/modules.d/77pollcdrom
%{dracutlibdir}/modules.d/77selinux
%{dracutlibdir}/modules.d/77syslog
%{dracutlibdir}/modules.d/77usrmount
%{dracutlibdir}/modules.d/78systemd-sysusers
%{dracutlibdir}/modules.d/80base
%{dracutlibdir}/modules.d/81busybox
%{dracutlibdir}/modules.d/84memstrack
%{dracutlibdir}/modules.d/85shell-interpreter
%{dracutlibdir}/modules.d/86shutdown

%ifarch s390 s390x
%{dracutlibdir}/modules.d/68cms
%{dracutlibdir}/modules.d/69cio_ignore
%{dracutlibdir}/modules.d/73zipl
%{dracutlibdir}/modules.d/74dasd
%{dracutlibdir}/modules.d/74dasd_mod
%{dracutlibdir}/modules.d/74dcssblk
%{dracutlibdir}/modules.d/74zfcp
%endif

%attr(0644,root,root) %ghost %config(missingok,noreplace) %{_localstatedir}/log/dracut.log
%dir %{_sharedstatedir}/initramfs
%if %{defined _unitdir}
%{_unitdir}/dracut-shutdown.service
%{_unitdir}/dracut-shutdown-onfailure.service
%{_unitdir}/sysinit.target.wants/dracut-shutdown.service
%{_unitdir}/dracut-cmdline.service
%{_unitdir}/dracut-initqueue.service
%{_unitdir}/dracut-mount.service
%{_unitdir}/dracut-pre-mount.service
%{_unitdir}/dracut-pre-pivot.service
%{_unitdir}/dracut-pre-trigger.service
%{_unitdir}/dracut-pre-udev.service
%{_unitdir}/initrd.target.wants/dracut-cmdline.service
%{_unitdir}/initrd.target.wants/dracut-initqueue.service
%{_unitdir}/initrd.target.wants/dracut-mount.service
%{_unitdir}/initrd.target.wants/dracut-pre-mount.service
%{_unitdir}/initrd.target.wants/dracut-pre-pivot.service
%{_unitdir}/initrd.target.wants/dracut-pre-trigger.service
%{_unitdir}/initrd.target.wants/dracut-pre-udev.service
%endif
%{_prefix}/lib/kernel/install.d/50-dracut.install

%files network
%{dracutlibdir}/modules.d/11systemd-networkd
%{dracutlibdir}/modules.d/35connman
%{dracutlibdir}/modules.d/35network-manager
%{dracutlibdir}/modules.d/40network
%{dracutlibdir}/modules.d/70kernel-network-modules
%{dracutlibdir}/modules.d/70qemu-net
%{dracutlibdir}/modules.d/74cifs
%{dracutlibdir}/modules.d/74fcoe
%{dracutlibdir}/modules.d/74fcoe-uefi
%{dracutlibdir}/modules.d/74iscsi
%{dracutlibdir}/modules.d/74nbd
%{dracutlibdir}/modules.d/74nfs
%{dracutlibdir}/modules.d/74nvmf
%{dracutlibdir}/modules.d/74ssh-client
%ifarch s390 s390x
%{dracutlibdir}/modules.d/74znet
%endif
%{dracutlibdir}/modules.d/70uefi-lib

%files caps
%{dracutlibdir}/modules.d/12caps

%files live
%{dracutlibdir}/modules.d/70img-lib
%{dracutlibdir}/modules.d/70dmsquash-live
%{dracutlibdir}/modules.d/70dmsquash-live-autooverlay
%{dracutlibdir}/modules.d/70dmsquash-live-ntfs
%{dracutlibdir}/modules.d/70livenet

%files tools
%if %{with doc}
%doc %{_mandir}/man8/dracut-catimages.8*
%endif

%{_bindir}/dracut-catimages
%dir /boot/dracut
%dir /var/lib/dracut
%dir /var/lib/dracut/overlay

%files squash
%{dracutlibdir}/modules.d/87squash
%{dracutlibdir}/modules.d/74squash-erofs
%{dracutlibdir}/modules.d/74squash-squashfs
%{dracutlibdir}/modules.d/88squash-lib

%files config-generic
%{dracutlibdir}/dracut.conf.d/02-generic-image.conf

%files config-rescue
%{dracutlibdir}/dracut.conf.d/02-rescue.conf
%{_prefix}/lib/kernel/install.d/51-dracut-rescue.install

%changelog
* Fri Sep 04 2026 John Meneghini <jmeneghi@redhat.com> - 112
- Naked clone of upstream dracut repo for Timberland SIG
