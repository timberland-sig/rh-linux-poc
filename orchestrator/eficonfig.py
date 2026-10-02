from typing import Dict, Any, Optional
from pathlib import Path

from orchestrator.defaults import DEFAULTS
from orchestrator.utils import cidr_to_netmask


class EFIConfigGenerator:
    """Generates host-vm/eficonfig/config for NVMe boot attempts."""

    def __init__(self, test: Dict[str, Any], environment: Dict[str, Any]):
        self.test = test
        self.environment = environment
        self.config_file = Path("host-vm/eficonfig/config")

    def _resolve_default(self, value: Any, field: str, attempt_idx: int) -> str:
        """Resolve 'default' values to actual values."""
        if value != 'default':
            return str(value)

        if field == 'macAddress':
            mac_key = f'HOST_MAC{attempt_idx + 2}'
            return DEFAULTS.get(mac_key, 'EA:EB:D3:58:89:58')

        elif field == 'hostIp':
            if attempt_idx == 0:
                host_ip = self.environment['network']['br1'].get('hostVmIp', '')
                return host_ip.split('/')[0] if host_ip else DEFAULTS.get('HOST_IP2', '192.168.101.30')
            elif attempt_idx == 1:
                host_ip = self.environment['network']['br2'].get('hostVmIp', '')
                return host_ip.split('/')[0] if host_ip else DEFAULTS.get('HOST_IP3', '192.168.110.30')
            else:
                return DEFAULTS.get('HOST_IP2', '192.168.101.30')

        elif field == 'targetIp':
            if attempt_idx == 0:
                target_ip = self.environment['network']['br1'].get('targetVmIp', '')
                return target_ip.split('/')[0] if target_ip else DEFAULTS.get('TARGET_IP2', '192.168.101.20')
            elif attempt_idx == 1:
                target_ip = self.environment['network']['br2'].get('targetVmIp', '')
                return target_ip.split('/')[0] if target_ip else DEFAULTS.get('TARGET_IP3', '192.168.110.20')
            else:
                return DEFAULTS.get('TARGET_IP2', '192.168.101.20')

        elif field == 'subsystemNQN':
            return DEFAULTS.get('SUBNQN', 'nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db')

        elif field == 'port':
            return DEFAULTS.get('SUBSYS_PORT', '4420')

        elif field == 'timeout':
            return '3000'

        return str(value)

    def _get_subnet_mask(self, attempt: Dict[str, Any], attempt_idx: int) -> str:
        """Get subnet mask for the boot attempt."""
        subnet_mask = attempt.get('subnetMask')

        if subnet_mask is not None:
            if isinstance(subnet_mask, int):
                return cidr_to_netmask(subnet_mask)
            elif subnet_mask == 'default':
                subnet_mask = 24
            else:
                return str(subnet_mask)

        if attempt_idx == 0:
            network_subnet = self.environment['network']['br1'].get('subnetMask', 24)
        elif attempt_idx == 1:
            network_subnet = self.environment['network']['br2'].get('subnetMask', 24)
        else:
            network_subnet = 24

        if isinstance(network_subnet, int):
            return cidr_to_netmask(network_subnet)
        return str(network_subnet)

    def _get_gateway(self, attempt_idx: int) -> str:
        """Get the Gateway for a boot attempt: the router's host-side IP when useRouter is enabled."""
        if not self.environment.get('useRouter', False):
            return '0.0.0.0'

        if attempt_idx == 0:
            return DEFAULTS.get('ROUTER_TO_HOST_IP2', '192.168.31.1')
        elif attempt_idx == 1:
            return DEFAULTS.get('ROUTER_TO_HOST_IP3', '192.168.32.1')
        else:
            return DEFAULTS.get('ROUTER_TO_HOST_IP2', '192.168.31.1')

    def _generate_attempt_config(self, attempt: Dict[str, Any], attempt_idx: int, attempt_num: int) -> str:
        """Generate configuration for a single boot attempt."""
        mac = self._resolve_default(attempt.get('macAddress', 'default'), 'macAddress', attempt_idx)
        host_ip = self._resolve_default(attempt.get('hostIp', 'default'), 'hostIp', attempt_idx)
        target_ip = self._resolve_default(attempt.get('targetIp', 'default'), 'targetIp', attempt_idx)
        nqn = self._resolve_default(attempt.get('subsystemNQN', 'default'), 'subsystemNQN', attempt_idx)
        port = self._resolve_default(attempt.get('port', 'default'), 'port', attempt_idx)
        timeout = self._resolve_default(attempt.get('timeout', 'default'), 'timeout', attempt_idx)
        subnet_mask = self._get_subnet_mask(attempt, attempt_idx)

        gateway = self._get_gateway(attempt_idx)
        if host_ip == 'dhcp':
            local_ip = '0.0.0.0'
            subnet_mask = '0.0.0.0'
            use_host_dhcp = "TRUE"
        else:
            local_ip = host_ip
            use_host_dhcp = "FALSE"

        config = f"""$Start
AttemptName:Attempt{attempt_num}
HostName:host-vm
MacString:{mac}
TargetPort:{port}
Enabled:1
IpMode:0
InitiatorInfoFromDhcp:{use_host_dhcp}
LocalIp:{local_ip}
SubnetMask:{subnet_mask}
Gateway:{gateway}
TargetIp:{target_ip}
NQN:{nqn}
ConnectTimeout:{timeout}
ConnectRetryCount:10
DnsMode:FALSE
$End"""
        return config

    def generate(self):
        """Generate the complete EFI configuration file."""
        host_id = self.test.get('host-uuid', DEFAULTS.get('HOST_SYS_UUID'))
        host_nqn = f'nqn.2014-08.org.nvmexpress:uuid:{host_id}'

        config_lines = [
            f"HostNqn:{host_nqn}",
            f"HostId:{host_id}"
        ]

        boot_attempts = self.test.get('bootAttempts', [])
        for idx, attempt in enumerate(boot_attempts):
            attempt_config = self._generate_attempt_config(attempt, idx, idx + 1)
            config_lines.append(attempt_config)

        config_content = '\n'.join(config_lines) + '\n'

        self.config_file.parent.mkdir(parents=True, exist_ok=True)

        with open(self.config_file, 'w') as f:
            f.write(config_content)

        print(f"✓ Generated EFI config: {self.config_file}")
        print(f"  - Host UUID: {host_id}")
        print(f"  - Boot attempts: {len(boot_attempts)}")

    def get_host_ip(self) -> Optional[str]:
        """Get the expected host VM IP address from first boot attempt."""
        boot_attempts = self.test.get('bootAttempts', [])
        if not boot_attempts:
            return None

        first_attempt = boot_attempts[0]
        host_ip = self._resolve_default(first_attempt.get('hostIp', 'default'), 'hostIp', 0)
        return host_ip