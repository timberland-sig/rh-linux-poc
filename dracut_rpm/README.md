# Timberland dracut

**NOTICE**: This is an expermental version of dracut
from the Timberland-sig repository. This library provides
additional support for NVMe/TCP boot with the Timberland-sig
version of libnvme and nvme-cli.

This rpm repository tracks the [Timberland
SIG](https://github.com/timberland-sig/dracut-ng.git) dracut_ng respository and
it may not be useful for current developement with Fedora or RHEL.

As of this writing, the current the upstream
[Fedora](https://src.fedoraproject.org/rpms/dracut) dracut repository
apparently has everything needed (incl. all of Martin's PRs).  So theoretically
you can use latest Fedora dracut rpms for Timberland SIG development. 

The thing is that the dracut in Fedora is heavily patched and some patches may
be needed for an installer e.g.. So unless you plan to backport all the patches
here, I'd advise to use official dracut rpms. Also, kdump may depend on some of
these dracut patches.

