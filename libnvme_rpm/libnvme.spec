# RHEL 8 compatibility
%{!?version_no_tilde: %define version_no_tilde %{shrink:%(echo '%{version}' | tr '~' '-')}}

Name: libnvme
Summary: Linux-native nvme device management library
Version: 1.4
Release: 1%{?dist}
License: LGPL-2.1-or-later
URL: https://github.com/timberland-sig/libnvme
Source: %{name}-%{version_no_tilde}.tar.gz
Group: Development/Tools
BuildRoot: %{_tmppath}/%{name}-root

BuildRequires: gcc gcc-c++
BuildRequires: swig
BuildRequires: python3-devel

BuildRequires: meson >= 0.50
BuildRequires: json-c-devel >= 0.13
BuildRequires: openssl-devel
BuildRequires: dbus-devel
%if (0%{?rhel} == 0)
BuildRequires: kernel-headers >= 5.15
%endif

%description
Provides type definitions for NVMe specification structures,
enumerations, and bit fields, helper functions to construct,
dispatch, and decode commands and payloads, and utilities to connect,
scan, and manage nvme devices on a Linux system.
NOTICE: This is an expermental version of the libnvme library
from the Timberland-sig repository. This library provides
additional types and definitions to support NVMe/TCP boot
with Timberland-sig version of nvme-cli and dracut.

%package devel
Summary: Development files for %{name}
Requires: %{name}%{?_isa} = %{version}-%{release}

%description devel
This package provides header files to include and libraries to link with
for Linux-native nvme device management.
%package doc
Summary: Reference manual for libnvme
BuildArch: noarch
BuildRequires: perl-interpreter
BuildRequires: python3-sphinx
BuildRequires: python3-sphinx_rtd_theme

%description doc
This package contains the reference manual for %{name}.

%package -n python3-libnvme
Summary:  Python3 bindings for libnvme
Requires: %{name}%{?_isa} = %{version}-%{release}
Provides:  python3-nvme = %{version}-%{release}
Obsoletes: python3-nvme < 1.0~rc7
%{?python_provide:%python_provide python3-libnvme}

%description -n python3-libnvme
This package contains Python bindings for libnvme.

%prep
%autosetup -c

%build
%meson -Dpython=true -Ddocs=all -Ddocs-build=true -Dhtmldir=%{_pkgdocdir}
%meson_build

%install
%meson_install
%{__install} -pm 644 README.md %{buildroot}%{_pkgdocdir}
%{__install} -pm 644 doc/config-schema.json %{buildroot}%{_pkgdocdir}
mv %{buildroot}%{_pkgdocdir}/nvme/html %{buildroot}%{_pkgdocdir}/html
rm -rf %{buildroot}%{_pkgdocdir}/nvme
mv %{buildroot}/usr/*.rst %{buildroot}%{_pkgdocdir}/

%ldconfig_scriptlets

%files
%license COPYING ccan/licenses/*
%{_libdir}/libnvme.so.1
%{_libdir}/libnvme.so.1.3.0
%{_libdir}/libnvme-mi.so.1
%{_libdir}/libnvme-mi.so.1.3.0

%files devel
%{_libdir}/libnvme.so
%{_libdir}/libnvme-mi.so
%{_includedir}/libnvme.h
%{_includedir}/libnvme-mi.h
%dir %{_includedir}/nvme
%{_includedir}/nvme/*.h
%{_libdir}/pkgconfig/*.pc

%files doc
%doc %{_pkgdocdir}
%{_mandir}/man2/*.2*

%files -n python3-libnvme
%dir %{python3_sitearch}/libnvme
%{python3_sitearch}/libnvme/*

%changelog
* Mon Feb 13 2023 John Meneghini <jmeneghi@redhat.com>
- Fix building rpms

* Tue Jan 31 2023 Tomas Bzatek <tbzatek@redhat.com> - 1.3-1
- Upstream v1.3 release

* Thu Jan 19 2023 Fedora Release Engineering <releng@fedoraproject.org> - 1.2-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_38_Mass_Rebuild

* Tue Nov 01 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.2-1
- Upstream v1.2 release

* Fri Aug 05 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.1-1
- Upstream v1.1 release

* Thu Jul 21 2022 Fedora Release Engineering <releng@fedoraproject.org> - 1.1~rc0-2
- Rebuilt for https://fedoraproject.org/wiki/Fedora_37_Mass_Rebuild

* Fri Jul 15 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.1~rc0-1
- Upstream v1.1 Release Candidate 0

* Mon Jun 13 2022 Python Maint <python-maint@redhat.com> - 1.0-2
- Rebuilt for Python 3.11

* Mon Apr 11 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0-1
- Upstream v1.0 release

* Fri Apr 01 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc8-1
- Upstream v1.0 Release Candidate 8

* Wed Mar 23 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc7-1
- Upstream v1.0 Release Candidate 7
- Renamed python3-nvme subpackage to python3-libnvme

* Mon Mar 14 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc6-1
- Upstream v1.0 Release Candidate 6

* Fri Mar 04 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc5-1
- Upstream v1.0 Release Candidate 5

* Mon Feb 28 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc4-1
- Upstream v1.0 Release Candidate 4

* Fri Feb 11 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc3-1
- Upstream v1.0 Release Candidate 3

* Tue Feb 01 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc2-1
- Upstream v1.0 Release Candidate 2

* Thu Jan 27 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc1-1
- Upstream v1.0 Release Candidate 1

* Mon Jan 17 2022 Tomas Bzatek <tbzatek@redhat.com> - 1.0~rc0-1
- Upstream v1.0 Release Candidate 0

* Wed Oct 20 2021 Tomas Bzatek <tbzatek@redhat.com> - 0.0.1-1.git1fe38d6
- Initial packaging
