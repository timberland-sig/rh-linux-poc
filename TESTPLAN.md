# NVMe/TCP Boot Test Plan

## Basic Test

The basic tests are run against a QEMU based linux soft target using a static
IPv4 multi-path configuration with two host-vm networks with two target-vm
controllers per network. This results in a multi-path configuratoin that
includes 4 paths to the nvme-of discovery and nvm subsystems on the target-vm,
and emulates the standard `dual-fabric` redundant configuration used by most
enterprise class storage arrays and nvme-of subsystems.

1. installation
2. cold boot
3. warm restart
4. kdump
5. multipath, full reboot with NIC #1 down
6. multipath, full reboot with NIC #2 down
7. multipath NIC #1 down + up during OS runtime
8. multipath NIC #2 down + up during OS runtime

The initial NBFT configuration should be run with the following Attempt
variables programmed for Attempts 1 and 2.

```
    MAC String:  xx:xx:xx:xx:xx
    Subsys IP:   xxx.xxx.xxx.xx
    Subsys PortId:4420
    Subsys NQN:   nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db
    Subsys NID:
    Host DHCP:    Disabled
    Subsys DHCP:  Disabled
    IP Mode:      0 (IPv4)
    Local IP:     xxx.xxx.xxx.xx
    Subnet Mask:  255.255.255.0
    Gateway:      0.0.0.0
    DNS Mode:     FALSE
```

## 1st dimension tests repeat the basic tests with the following additional NBFT configurations.

1. static IPv4, Subsystem NQN, with gateway
2. static IPv4, Subsystem NQN, with gateway, using different subnet masks

Attempt variables programmed for Attempts 1 and 2.

```
    MAC String:  xx:xx:xx:xx:xx
    Subsys IP:   xxx.xxx.xxx.xx
    Subsys PortId:4420
    Subsys NQN:   nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db
    Subsys NID:
    Host DHCP:    Disabled
    Subsys DHCP:  Disabled
    IP Mode:      0 (IPv4)
    Local IP:     xxx.xxx.xxx.xx
    Subnet Mask:  xxx.xxx.xxx.xxx
    Gateway:      xxx.xxx.xxx.xxx
    DNS Mode:     FALSE
```

## 2nd dimension tests adds the following the 1st dimension tests

1. Discovery NQN
2. Discovery NQN + NID

Attempt variables programmed for Attempts 1 and 2.

```
    MAC String:  xx:xx:xx:xx:xx
    Subsys IP:   xxx.xxx.xxx.xxx
    Subsys PortId:4420
    Subsys NQN:  nqn.2014-08.org.nvmexpress.discovery
    Subsys NID:  xxxxxxxxx
    Host DHCP:    Disabled
    Subsys DHCP:  Disabled
    IP Mode:      0 (IPv4)
    Local IP:     xxx.xxx.xxx.xxx
    Subnet Mask:  xxx.xxx.xxx.xxx
    Gateway:      xxx.xxx.xxx.xxx
    DNS Mode:     FALSE
```

## Target Storage array testing:

The Target Storage array tests repeat the above demension 1 and 2 test
configurations and tests with the following hardware.

1. NetApp ONTAP
2. HPE Alletra
3. Pure Storage
4. Lightbits*
5. Dell PowerStore, no CDC*
6. Dell PowerStore with CDC (Central Discovery Controller)*

* = not required for upstream acceptance.

Attempt variables programmed for Attempts 1 and 2 with Storage Arrays will
include changing the `Subsys PortId` to 8009 when the Discovery NQN is used.

```
    MAC String:  xx:xx:xx:xx:xx
    Subsys IP:   xxx.xxx.xxx.xxx
    Subsys PortId:8009/4420
    Subsys NQN:  nqn.2014-08.org.nvmexpress.discovery
    Subsys NID:  xxxxxxxxx
    Host DHCP:    Disabled
    Subsys DHCP:  Disabled
    IP Mode:      0 (IPv4)
    Local IP:     xxx.xxx.xxx.xxx
    Subnet Mask:  xxx.xxx.xxx.xxx
    Gateway:      xxx.xxx.xxx.xxx
    DNS Mode:     FALSE
```

## Test Details

NVMe-TCP FIO Stress Test with NVMe-TCP BFS

### Basic Testing

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

### NVMe-TCP reset_controller during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Reset controllers with IO in progress
3. Verify Expected Results

### NVMe-TCP reset_controller stress with NVMe-TCP BFS

1. Repeat Basic Testing
2. Reset controllers repeatedly with IO in progress
3. Verify Expected Results


### NVMe-TCP rescan/reset_controller during I/O with NVMe-TCP BFS
1. Repeat Basic Testing
2. Rescan controllers with IO in progress
3. Verify Expected Results

### NVMe-TCP Offline CPU during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Offline/Online CPUs with IO in progress
3. Verify Expected Results


### NVMe-TCP connect/delete stress tests with NVMe-TCP BFS

1. Repeat Basic Testing
2. Add/Remove connections with IO in progress
3. Verify Expected Results

### NVMe-TCP Port Toggle with I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Toggle swich ports off/on with IO in progress
3. Verify Expected Results

### NVMe-TCP Array Controller Failover during I/O with NVMe-TCP BFS

1. Repeat Basic Testing
2. Initiate controller failover/givebacke with IO in progress
3. Verify Expected Results

### NVMe-TCP Reboot Test with NVMe-TCP BFS

1. Repeat Basic Testing
2. Disable the switchport associated with NVMe-oF Subsystem
3. Reboot the host
2. Enable the switchport associated with NVMe-oF Subsystem
3. Verify Expected Results

Expected Results

* System successfully reboots
* System recovers all paths successfully after switchport is enabled following reboot

## 3rd dimension tests adds the following the 1st and 2nd dimension tests

The 3rd dimenstion tests are a strech goal and are note required for upstream acceptance.

1. IPv4 with Host DHCP address
2. IPv4 with Subsys DHCP address
3. IPv4 with Host and Subsys DHCP address

Attempt variables programmed for Attempts 1 and 2.

```
    MAC String:  xx:xx:xx:xx:xx
    Subsys IP:   0,0,0,0
    Subsys PortId:4420
    Subsys NQN:   nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db
    Subsys NID:
    Host DHCP:    Enabled
    Subsys DHCP:  Enabled
    IP Mode:      0 (IPv4)
    Local IP:     0.0.0.0
    Subnet Mask:  0.0.0.0
    Gateway:      0.0.0.0
    xxx.xxx.xxx.xxx
    DNS Mode:     FALSE
```

## 4th dimension tests - IPV6

The 4th dimenstion tests are for future reference and will not be run prior to
upstream submission. The 4th dimension tests adds IPV6 to the above nbft
configuraitons.

**Note** IPv6 support is not needed for upstream acceptance.

Attempt variables programmed for Attempts 1 and 2.

```
    MAC String:  xx:xx:xx:xx:xx
    Subsys IP:   xxx.xxx.xxx.xxx
    Subsys PortId: xxxx
    Subsys NQN:  nqn.2014-08.org.nvmexpress.discovery
    Subsys NID:  xxxxxxxxx
    Host DHCP:    Enabled/Disabled
    Subsys DHCP:  Enabled/Disabled
    IP Mode:      1 (IPv6)
    Local IP:     xxx.xxx.xxx.xxx
    Subnet Mask:  xxx.xxx.xxx.xxx
    Gateway:      xxx.xxx.xxx.xxx
    DNS Mode:     FALSE
```
