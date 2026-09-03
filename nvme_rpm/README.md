# Timberland nvme-cli 

**NOTICE**: This is an expermental version of nvme-cli
from the Timberland-sig repository.  This utility provides
additional support for NVMe/TCP boot with the Timberland-sig
libnvme and dracut libraries.

This rpm repository tracks the [Timberland
SIG nvm-cli](https://github.com/timberland-sig/nvme-cli.git) nvme-cli respository and
should be used for Timberland SIG development with Fedora and RHEL.

As of this writing, the current the upstream [Fedora
nvme-cli](https://src.fedoraproject.org/rpms/nvme-cli) repository does not
contain a libnvme 3.0 library. This is needed for testing and development with 
the current [Timberland SIG EDK2](https://github.com/timberland-sig/edk2) code. 
