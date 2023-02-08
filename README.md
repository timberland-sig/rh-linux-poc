# Red Hat NVMe/TCP Boot prototype

This directory contains packages, scripts and instructions to assit in the set up and deployment of a QEMU based NVMe/TCP boot POC. The prerequisites for this POC include:

1. An X86_64 based hardware platform with 32GB of memory, 12 (VT-x) cores, at least 200GB of spare storage space, and a hardwired ethernet connection with access to the public network.
2. A recent version of CentOS Stream 9, RHEL 9 or Fedora 36/37 installed - this will be your hypervisor.
3. Full root privileges so you can administer the hypervisor.

I developed this POC on a [ThinkPad T Series Laptop](https://www.lenovo.com/us/en/c/laptops/thinkpad/thinkpadt) using a modified version of RHEL 8.7 with an [upstream QEMU library](https://www.qemu.org/download/) installed. Note that QEMU version distributed with  CensOS 8 and RHEL 8 will not supportthis POC. It's best to use a current version of Fedora or Centos 9 as you will need an up-to-date version of QEMU.

# How does it work:

We need to create and install a bootable image on the Remote machine which will service the boot device though the NVMe/TCP protocol.  It doesn't really matter what you NVMe/TCP target looks like.  The Remote NVMe/TCP target implentation could be a NVMe/TCP storage array or a Linux soft target. The NVMe Namespace simply needs to be served by some NVMe/TCP target. This POC includes instructions on how to setup a Linux soft target using a QEMU VM. 

On the local machine we will execute the UEFI firmware with QEMU, the firmware will connect to the remote target, load the kernel and the latter will take over the boot process by using the
information provided by the UEFI firmware via the NBFT table.

```
         Local Machine                                              Remote Machine

       ------------------                                      -----------------------

       |    CentOS 9    |                                      |                     |

       |   QEMU + UEFI  |                                      |   NVMe/TCP target   |

       |   + EFIDISK    |      -------> LAN --------->         |     RHEL rootfs     |

       |                |                                      |                     |

       ------------------                                      -----------------------
```

# Set up your Hypervisor

# Prepare the Centos 9 Local Machine

Download a current [CentOS Stream 9 ISO](https://mirrors.centos.org/mirrorlist?path=/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso&redirect=1&protocol=https) and save it in a directory on your hypervisor/host.

Install a RHEL9.2 VM that we will use as a target:

```
$ qemu-system-x86_64 --enable-kvm -bios OVMF-pure-efi.fd -drive file=rhel9disk_target,if=none,id=NVME1
-device nvme,drive=NVME1,serial=nvme-1,physical_block_size=4096,logical_block_size=4096 -cpu host
-net user -net nic -cdrom rhel9.2.iso -boot d -m 8G
```

WARNING: remember to set the disk's logical and physical block size to 4096 bytes.
You can download the OVMF-pure-efi bios image here

Boot the newly installed VM and read the grub.cfg file:

```
# cat /boot/efi/EFI/redhat/grub.cfg
search --no-floppy --fs-uuid --set=dev 877ea44d-0b8b-4abd-b777-9294757abfd0 <---
set prefix=($dev)/grub2
```

Copy the device's UUID, we will need it later

Download the RHEL9.2 kernel with the timberland patches and install it on the VM.
Download the timberland dracut RPM packages and install them.
Download the timberland libnvme RPM packages and install them.
Download the timberland nvme-cli RPM and install it.

