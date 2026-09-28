# NVMe/TCP Boot Test Plan

## Basic Testing

The basic tests are run against a QEMU based linux soft target using a static
IPv4 multi-path configuration with two `host-vm` networks with two `target-vm`
controllers per network. This results in a multi-path configuratoin that
includes 4 paths to the NVMe-oF discovery and NVM subsystems on the `target-vm`,
and emulates the standard _dual-fabric_ redundant configuration used by most
enterprise class storage arrays and NVMe-oF subsystems.

1. installation
2. cold boot
3. warm restart
4. kdump
5. multipath, full reboot with NIC #1 down
6. multipath, full reboot with NIC #2 down
7. multipath NIC #1 down + up during OS runtime
8. multipath NIC #2 down + up during OS runtime

For more information about these tests, see the Test Details section of this Test Plan.

### Test Details

1. Provision system to install onto the NVMe-TCP namespace and verify when the installation is complete:
2. Upon bootup, the nvme connections are already made:
3. Multipathing is enabled and working:
4. Generate I/O with FIO:

Expected Results

* FIO Completes
* No Data Errors
* No Kernel Stack Traces
* No Kernel Panics
* No Hangs
* Optimized Paths are available after test completes
* Non-Optimized Paths are available after test completes

#### NVMe-TCP reset_controller during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Reset controllers with IO in progress
3. Verify Expected Results

#### NVMe-TCP reset_controller stress with NVMe-TCP BFS

1. Repeat Basic Testing
2. Reset controllers repeatedly with IO in progress
3. Verify Expected Results


#### NVMe-TCP rescan/reset_controller during I/O with NVMe-TCP BFS
1. Repeat Basic Testing
2. Rescan controllers with IO in progress
3. Verify Expected Results

#### NVMe-TCP Offline CPU during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Offline/Online CPUs with IO in progress
3. Verify Expected Results

#### NVMe-TCP connect/delete stress tests with NVMe-TCP BFS

1. Repeat Basic Testing
2. Add/Remove connections with IO in progress
3. Verify Expected Results

#### NVMe-TCP Port Toggle with I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Toggle swich ports off/on with IO in progress
3. Verify Expected Results

#### NVMe-TCP Array Controller Failover during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Initiate controller failover/giveback with IO in progress
3. Verify Expected Results

#### NVMe-TCP Reboot Test with NVMe-TCP BFS

1. Repeat Basic Testing
2. Disable the switchport associated with NVMe-oF Subsystem
3. Reboot the host
4. Enable the switchport associated with NVMe-oF Subsystem
5. Verify Expected Results

Expected Results

* System successfully reboots
* System recovers all paths successfully after switchport is enabled following reboot

## Feature development

Prior to upstream submission, support for the following NVMe/TCP boot features will be developed and tested:

1. static non-routed IPv4 support
2. static routed IPv4 support
3. static non-routed IPv6 support
4. static routed IPv6 support
5. support for Discovery NQNs
6. support for NIDs
7. support for different NVMe-oF Targets and Controllers (not just the Linux Soft Target)
8. support for all [EDK2 CPU](https://github.com/timberland-sig/edk2/issues/71) Architectures

Features not required for upstream submission will include:

1. support for IPv4 dynamic addressing with DHCP
2. support for IPv6 dynamic addressing with DHCP

Features are expressed in terms of the their NBFT configurations.  The Basic
Tests are run with different `NBFT Attempt` configurations.

### Static non-routed IPv4

The initial NBFT configuration should be run with the following Attempt
variables programmed for Attempts 1 and 2.

Key: xxx denotes a programmable NBFT value.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxx.xxx.xxx.xx
    Subsys PortId: 4420
    Subsys NQN:    nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db
    Subsys NID:
    Host DHCP:     Disabled
    Subsys DHCP:   Disabled
    IP Mode:       0 (IPv4)
    Local IP:      xxx.xxx.xxx.xx
    Subnet Mask:   255.255.255.0
    Gateway:       0.0.0.0
    DNS Mode:      FALSE
```

### Static routed IPv4

Repeat the Basic Tests with the following additional NBFT configurations:

1. static IPv4, Subsystem NQN, with gateway
2. static IPv4, Subsystem NQN, with gateway, using different subnet masks

Attempt variables programmed for Attempts 1 and 2.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxx.xxx.xxx.xx
    Subsys PortId: 4420
    Subsys NQN:    nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db
    Subsys NID:
    Host DHCP:     Disabled
    Subsys DHCP:   Disabled
    IP Mode:       0 (IPv4)
    Local IP:      xxx.xxx.xxx.xx
    Subnet Mask:   xxx.xxx.xxx.xxx
    Gateway:       xxx.xxx.xxx.xxx
    DNS Mode:      FALSE
```

### Static non-routed IPv6

The initial NBFT configuration should be run with the following Attempt
variables programmed for Attempts 1 and 2.

Key: xxx denotes a programmable NBFT value.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxx.xxx.xxx.xx
    Subsys PortId: 4420
    Subsys NQN:    nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db
    Subsys NID:
    Host DHCP:     Disabled
    Subsys DHCP:   Disabled
    IP Mode:       1 (IPv6)
    Local IP:      xxx.xxx.xxx.xx
    Subnet Mask:   xxx.xxx.xxx.xx
    Gateway:       0
    DNS Mode:      FALSE
```

### Static routed IPv6

Repeat the Basic Tests with the following additional NBFT configurations:

1. static IPv6, Subsystem NQN, with gateway
2. static IPv6, Subsystem NQN, with gateway, using different subnet masks

Attempt variables programmed for Attempts 1 and 2.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxx.xxx.xxx.xx
    Subsys PortId: 4420
    Subsys NQN:    nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db
    Subsys NID:
    Host DHCP:     Disabled
    Subsys DHCP:   Disabled
    IP Mode:       1 (IPv6)
    Local IP:      xxx.xxx.xxx.xx
    Subnet Mask:   xxx.xxx.xxx.xxx
    Gateway:       xxx.xxx.xxx.xxx
    DNS Mode:      FALSE
```

### Discovery NQN + NID support

Repeat the Basic Tests with the following additional NBFT configurations.

1. Discovery NQN
2. Discovery NQN + NID

Attempt variables programmed for Attempts 1 and 2.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxx.xxx.xxx.xxx
    Subsys PortId: xxxx
    Subsys NQN:    nqn.2014-08.org.nvmexpress.discovery
    Subsys NID:    xxxxxxxxx
    Host DHCP:     Disabled
    Subsys DHCP:   Disabled
    IP Mode:       0 (IPv4)
    Local IP:      xxx.xxx.xxx.xxx
    Subnet Mask:   xxx.xxx.xxx.xxx
    Gateway:       xxx.xxx.xxx.xxx
    DNS Mode:      FALSE
```

### Storage Array Tests

All of the above tests will be run against a collection of storage array targets.

The Target Storage array tests repeat the above NBFT test configurations with the following hardware:

1. NetApp ONTAP
2. HPE Alletra
3. Pure Storage
4. Lightbits*
5. Dell PowerStore, no CDC*
6. Dell PowerStore with CDC (Central Discovery Controller)*

* = not required for upstream acceptance.

Attempt variables programmed for Attempts 1 and 2 with Storage Arrays will include changing the `Subsys PortId` to 8009 when the Discovery NQN is used.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxx.xxx.xxx.xxx
    Subsys PortId: 8009 or 4420
    Subsys NQN:    nqn.2014-08.org.nvmexpress.discovery or subsys.nqn
    Subsys NID:    xxxxxxxxx
    Host DHCP:     Disabled
    Subsys DHCP:   Disabled
    IP Mode:       0 (IPv4)
    Local IP:      xxx.xxx.xxx.xxx
    Subnet Mask:   xxx.xxx.xxx.xxx
    Gateway:       xxx.xxx.xxx.xxx
    DNS Mode:      FALSE
```

## Advanced Feature support

**Note** Support for these features is not needed for upstream acceptance.

### IPv4 with DHCP

Support for the following IPv4 features may be tested but they are not required for upstream submission.

1. IPv4 with Host DHCP address
2. IPv4 with Subsystem DHCP address
3. IPv4 with Host and Subsystem DHCP address

Attempt variables programmed for Attempts 1 and 2.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    Subsys PortId: xxxx
    Subsys NQN:    nqn.2014-08.org.nvmexpress.discovery / uuid:
    Subsys NID:    xxxxxxxxx
    Host DHCP:     Enabled
    Subsys DHCP:   Enabled
    IP Mode:       0 (IPv4)
    Local IP:      xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    Subnet Mask:   xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    Gateway:       xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    DNS Mode:      FALSE
```

### IPv6 with DHCP

Support for the following IPv6 features may be tested but they are not required for upstream submission.

4. IPv6 with Host DHCP address
5. IPv6 with Subsystem DHCP address
6. IPv6 with Host and Subsystem DHCP address

Attempt variables programmed for Attempts 1 and 2.

```
    MAC Address:   xx:xx:xx:xx:xx
    Subsys IP:     xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    Subsys PortId: xxxx
    Subsys NQN:    nqn.2014-08.org.nvmexpress.discovery / uuid:
    Subsys NID:    xxxxxxxxx
    Host DHCP:     Enabled
    Subsys DHCP:   Enabled
    IP Mode:       1 (IPv6)
    Local IP:      xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    Subnet Mask:   xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    Gateway:       xxxx::xxxx:xxxx:xxxx:xxxx:xxxx
    DNS Mode:      FALSE
```
