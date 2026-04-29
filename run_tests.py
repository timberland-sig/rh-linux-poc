#!/usr/bin/env python3
"""
NVMe/TCP Test Runner

Reads test configurations from tests.json, validates against schema,
sets up network environments, generates EFI boot configurations,
and runs boot tests using pytest.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
import socket
import warnings
import paramiko
from pathlib import Path
from typing import Dict, List, Any, Optional
import pytest


warnings.formatwarning = lambda msg, *args, **kwargs: f"Warning: {msg}\n"

# Default values for test configuration, matching defaults.sh
DEFAULTS = {
    'HOST_SYS_UUID': 'f8131bac-cdef-4165-866b-5998c1e67890',
    'HOST_MAC2': 'EA:EB:D3:58:89:58',
    'HOST_MAC3': 'EA:EB:D3:59:89:59',
    'HOST_IP2': '192.168.101.30',
    'HOST_IP3': '192.168.110.30',
    'TARGET_IP2': '192.168.101.20',
    'TARGET_IP3': '192.168.110.20',
    'SUBNQN': 'nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db',
}


SCRIPT_DIR = Path(__file__).parent
ARTIFACTS_DIR = SCRIPT_DIR / "artifacts"


def sanitize_dir_name(name: str) -> str:
    """Convert a test name to a short, terminal-friendly directory name."""
    name = name.lower()
    name = re.sub(r'[^a-z0-9]+', '-', name)
    name = name.strip('-')
    return name


def validate_schema(config: Dict[str, Any], schema_file: str) -> bool:
    """Validate test configuration against JSON schema."""
    try:
        import jsonschema
        with open(schema_file, 'r') as f:
            schema = json.load(f)
        jsonschema.validate(config, schema)
        print(f"✓ Schema validation passed")
        return True
    except ImportError:
        print("Warning: jsonschema module not found, skipping validation")
        print("Install with: pip install jsonschema")
        return True
    except jsonschema.exceptions.ValidationError as e:
        print(f"✗ Schema validation failed: {e.message}")
        return False


def load_test_config(test_file: str, schema_file: str) -> Dict[str, Any]:
    """Load and validate test configuration."""
    with open(test_file, 'r') as f:
        config = json.load(f)

    if not validate_schema(config, schema_file):
        raise ValueError("Test configuration failed schema validation")

    return config


def prepare_environment(environment: Dict[str, Any]):
    """Setup network and target-vm for an environment."""
    network_setup = NetworkSetup(environment['network'], SCRIPT_DIR)

    network_setup.setup()
    network_setup.setup_target_vm()


def generate_test_config(test: Dict[str, Any], environment: Dict[str, Any]):
    """Generate EFI configuration for a test."""
    efi_config = EFIConfigGenerator(
        test=test,
        environment=environment,
    )
    efi_config.generate()


class NetworkSetup:
    """Handles network bridge setup and target-vm startup."""

    def __init__(self, network_config: Dict[str, Any], script_dir: Path):
        self.network_config = network_config
        self.script_dir = script_dir
        self.target_vm_dir = script_dir / "target-vm"

    def _netmask_to_cidr(self, netmask: str) -> int:
        """Convert dotted decimal netmask to CIDR prefix length."""
        octets = netmask.split('.')
        if len(octets) != 4:
            return 24  # Default fallback

        try:
            # Convert to 32-bit integer
            mask = (int(octets[0]) << 24) | (int(octets[1]) << 16) | (int(octets[2]) << 8) | int(octets[3])
            # Count consecutive 1 bits from the left
            count = 0
            bitmask = (1 << 31)
            for i in range(32):
                if mask & bitmask:
                    count += 1
                else:
                    break
                bitmask >>= 1
            return count
        except (ValueError, IndexError):
            return 24  # Default fallback

    def _build_setup_args(self) -> List[str]:
        """Build command line arguments for ./setup.sh net."""
        args = []

        for bridge in ['br0', 'virbr1', 'virbr2']:
            if bridge not in self.network_config:
                print(f"Warning: {bridge} not found in network config")
                args.extend(['none', 'dhcp'])
                continue

            bridge_config = self.network_config[bridge]
            slave = bridge_config.get('slave', 'none')
            hypervisor_ip = bridge_config.get('hypervisorIp', 'dhcp')

            # Convert to CIDR notation if not 'dhcp' and not already in CIDR format
            if hypervisor_ip != 'dhcp' and '/' not in hypervisor_ip:
                subnet_mask = bridge_config.get('subnetMask', 24)

                # Convert subnet_mask to CIDR prefix length
                if isinstance(subnet_mask, str) and '.' in subnet_mask:
                    # It's a dotted decimal netmask, convert it
                    prefix_length = self._netmask_to_cidr(subnet_mask)
                else:
                    # It's already a CIDR prefix length
                    prefix_length = int(subnet_mask)

                hypervisor_ip = f"{hypervisor_ip}/{prefix_length}"

            args.append(slave)
            args.append(hypervisor_ip)

        return args

    def _check_target_vm_disk(self) -> bool:
        """Check if target-vm disk exists and has non-zero size."""
        disk_path = self.target_vm_dir / "disks" / "rh-boot.qcow2"

        if not disk_path.exists():
            print(f"✗ Target VM disk not found: {disk_path}")
            print("  Please set up the target-vm first by running:")
            print("    cd target-vm && make rh-install")
            return False

        try:
            disk_size = disk_path.stat().st_size
            if disk_size == 0:
                print(f"✗ Target VM disk is empty: {disk_path}")
                print("  Please set up the target-vm first by running:")
                print("    cd target-vm && make rh-install")
                return False

            print(f"✓ Target VM disk found: {disk_path} ({disk_size / (1024**3):.2f} GB)")
            return True
        except Exception as e:
            print(f"✗ Error checking target VM disk: {e}")
            return False

    def _get_target_cidr_env(self) -> Dict[str, str]:
        """Build environment variables for TARGET_CIDR from network config."""
        env = os.environ.copy()

        # Extract target IPs and subnet masks from network config
        for bridge_name, bridge_key in [('virbr1', 'virbr1'), ('virbr2', 'virbr2')]:
            if bridge_key not in self.network_config:
                continue

            bridge_config = self.network_config[bridge_key]
            target_ip = bridge_config.get('targetVmIp', '')
            subnet_mask = bridge_config.get('subnetMask', 24)

            if len(target_ip) == 0:
                continue

            # Ensure we have CIDR notation
            if '/' not in target_ip:
                if isinstance(subnet_mask, str) and '.' in subnet_mask:
                    # Convert dotted decimal to CIDR
                    prefix_length = self._netmask_to_cidr(subnet_mask)
                else:
                    prefix_length = int(subnet_mask)
                target_cidr = f"{target_ip}/{prefix_length}"
            else:
                target_cidr = target_ip

            # Set TARGET_IP2 for virbr1, TARGET_IP3 for virbr2
            if bridge_key == 'virbr1':
                env['TARGET_CIDR2'] = target_cidr
            elif bridge_key == 'virbr2':
                env['TARGET_CIDR3'] = target_cidr

        return env

    def setup_target_vm(self):
        """Setup and start the target-vm."""
        print("\n" + "="*70)
        print("Setting up target-vm")
        print("="*70)

        # Check disk exists
        if not self._check_target_vm_disk():
            raise RuntimeError("Target VM disk not ready")

        # Prepare environment with TARGET_CIDR variables
        env = self._get_target_cidr_env()

        # Start target-vm with make rh-start
        # Use Popen + wait() instead of subprocess.run() with capture_output,
        # because the backgrounded QEMU process inherits the pipes and prevents
        # communicate() from returning even after make itself exits.
        print("Starting target-vm with 'make rh-start'...")
        try:
            proc = subprocess.Popen(
                ['make', 'rh-start'],
                cwd=self.target_vm_dir,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                proc.wait(timeout=5)
            finally:
                proc.stdout.close()
                proc.stderr.close()

            if proc.returncode != 0:
                print(f"✗ Failed to start target-vm (exit code: {proc.returncode})")
                raise RuntimeError("Failed to start target-vm")

        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            print("✗ 'make rh-start' timed out")
            raise RuntimeError("Target-vm startup timed out")
        except FileNotFoundError:
            print(f"✗ Make not found or target-vm directory missing")
            raise RuntimeError("Cannot start target-vm")

        # Verify QEMU process is actually running
        result = subprocess.run(
            ['make', 'is-running'],
            cwd=self.target_vm_dir,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print("✗ QEMU process is not running")
            raise RuntimeError("Target-vm QEMU process failed to start")
        print("✓ Target-vm started")

        # Run netsetup.sh with timeout
        print("Configuring target-vm network with './netsetup.sh localhost'...")
        netsetup_script = self.script_dir / "vm-lib" / "netsetup.sh"

        try:
            result = subprocess.run(
                [str(netsetup_script), 'localhost'],
                cwd=self.target_vm_dir,
                env=env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=60
            )

            if result.returncode != 0:
                print(f"✗ netsetup.sh failed (exit code: {result.returncode})")
                if result.stdout:
                    print(f"Output:\n{result.stdout}")
                if result.stderr:
                    print(f"Error:\n{result.stderr}")
                raise RuntimeError("Target-vm network setup failed")

            print("✓ Target-vm network configured")
            if result.stdout:
                print(f"Output:\n{result.stdout}")
        except subprocess.TimeoutExpired as e:
            print("✗ netsetup.sh timed out after 60 seconds")
            if e.stdout:
                print(f"Output before timeout:\n{e.stdout.decode() if isinstance(e.stdout, bytes) else e.stdout}")
            if e.stderr:
                print(f"Errors before timeout:\n{e.stderr.decode() if isinstance(e.stderr, bytes) else e.stderr}")
            raise RuntimeError("Target-vm network setup timed out")
        except FileNotFoundError:
            print(f"✗ netsetup.sh not found: {netsetup_script}")
            raise RuntimeError(f"netsetup.sh not found: {netsetup_script}")

        print("✓ Target-vm setup complete")

    def teardown(self):
        """Execute network teardown."""
        teardown_script = self.script_dir / "teardown.sh"
        cmd = [str(teardown_script), 'net']

        print(f"Running: {' '.join(cmd)}")

        try:
            result = subprocess.run(
                cmd,
                cwd=self.script_dir,
                capture_output=True,
                text=True,
                timeout=60
            )

            if result.returncode == 0:
                print("✓ Network teardown completed successfully")
            else:
                print(f"✗ Network teardown failed with code {result.returncode}")
                if result.stderr:
                    print(f"Error:\n{result.stderr}")
                raise RuntimeError(f"Network teardown failed with exit code {result.returncode}")
        except subprocess.TimeoutExpired:
            print("✗ Network teardown timed out")
            raise RuntimeError("Network teardown timed out")
        except FileNotFoundError:
            print(f"✗ Teardown script not found: {teardown_script}")
            raise RuntimeError(f"Teardown script not found: {teardown_script}")

    def setup(self):
        """Execute network setup."""
        args = self._build_setup_args()

        print("Network configuration:")
        for i, bridge in enumerate(['br0', 'virbr1', 'virbr2']):
            slave_idx = i * 2
            ip_idx = i * 2 + 1
            print(f"  {bridge}: slave={args[slave_idx]}, ip={args[ip_idx]}")

        setup_script = self.script_dir / "setup.sh"
        cmd = [str(setup_script), 'net'] + args

        print(f"\nRunning: {' '.join(cmd)}")

        try:
            result = subprocess.run(
                cmd,
                cwd=self.script_dir,
                capture_output=True,
                text=True,
                timeout=300
            )

            if result.returncode == 0:
                print("✓ Network setup completed successfully")
            else:
                print(f"✗ Network setup failed with code {result.returncode}")
                if result.stderr:
                    print(f"Error:\n{result.stderr}")
                raise RuntimeError(f"Network setup failed with exit code {result.returncode}")
        except subprocess.TimeoutExpired:
            print("✗ Network setup timed out after 5 minutes")
            raise RuntimeError("Network setup timed out after 5 minutes")
        except FileNotFoundError:
            print(f"✗ Setup script not found: {setup_script}")
            raise RuntimeError(f"Setup script not found: {setup_script}")


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
                host_ip = self.environment['network']['virbr1'].get('hostVmIp', '')
                return host_ip.split('/')[0] if host_ip else DEFAULTS.get('HOST_IP2', '192.168.101.30')
            elif attempt_idx == 1:
                host_ip = self.environment['network']['virbr2'].get('hostVmIp', '')
                return host_ip.split('/')[0] if host_ip else DEFAULTS.get('HOST_IP3', '192.168.110.30')
            else:
                return DEFAULTS.get('HOST_IP2', '192.168.101.30')

        elif field == 'targetIp':
            if attempt_idx == 0:
                target_ip = self.environment['network']['virbr1'].get('targetVmIp', '')
                return target_ip.split('/')[0] if target_ip else DEFAULTS.get('TARGET_IP2', '192.168.101.20')
            elif attempt_idx == 1:
                target_ip = self.environment['network']['virbr2'].get('targetVmIp', '')
                return target_ip.split('/')[0] if target_ip else DEFAULTS.get('TARGET_IP3', '192.168.110.20')
            else:
                return DEFAULTS.get('TARGET_IP2', '192.168.101.20')

        elif field == 'subsystemNQN':
            return DEFAULTS.get('SUBNQN', 'nqn.2014-08.org.nvmexpress:uuid:0c468c4d-a385-47e0-8299-6e95051277db')

        elif field == 'port':
            return '4420'

        elif field == 'timeout':
            return '3000'

        return str(value)

    def _cidr_to_netmask(self, cidr: int) -> str:
        """Convert CIDR prefix length to dotted decimal netmask."""
        mask = (0xffffffff >> (32 - cidr)) << (32 - cidr)
        return f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"

    def _get_subnet_mask(self, attempt: Dict[str, Any], attempt_idx: int) -> str:
        """Get subnet mask for the boot attempt."""
        subnet_mask = attempt.get('subnetMask')

        if subnet_mask is not None:
            if isinstance(subnet_mask, int):
                return self._cidr_to_netmask(subnet_mask)
            elif subnet_mask == 'default':
                subnet_mask = 24
            else:
                return str(subnet_mask)

        if attempt_idx == 0:
            network_subnet = self.environment['network']['virbr1'].get('subnetMask', 24)
        elif attempt_idx == 1:
            network_subnet = self.environment['network']['virbr2'].get('subnetMask', 24)
        else:
            network_subnet = 24

        if isinstance(network_subnet, int):
            return self._cidr_to_netmask(network_subnet)
        return str(network_subnet)

    def _generate_attempt_config(self, attempt: Dict[str, Any], attempt_idx: int, attempt_num: int) -> str:
        """Generate configuration for a single boot attempt."""
        mac = self._resolve_default(attempt.get('macAddress', 'default'), 'macAddress', attempt_idx)
        host_ip = self._resolve_default(attempt.get('hostIp', 'default'), 'hostIp', attempt_idx)
        target_ip = self._resolve_default(attempt.get('targetIp', 'default'), 'targetIp', attempt_idx)
        nqn = self._resolve_default(attempt.get('subsystemNQN', 'default'), 'subsystemNQN', attempt_idx)
        port = self._resolve_default(attempt.get('port', 'default'), 'port', attempt_idx)
        timeout = self._resolve_default(attempt.get('timeout', 'default'), 'timeout', attempt_idx)
        subnet_mask = self._get_subnet_mask(attempt, attempt_idx)

        config = f"""$Start
AttemptName:Attempt{attempt_num}
HostName:host-vm
MacString:{mac}
TargetPort:{port}
Enabled:1
IpMode:0
LocalIp:{host_ip}
SubnetMask:{subnet_mask}
Gateway:0.0.0.0
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


class VMRunner:
    """Handles VM lifecycle - setup, start, and health checks."""

    def __init__(self, host_vm_dir: Path):
        self.host_vm_dir = host_vm_dir

    def setup(self) -> bool:
        """Run make setup in host-vm directory."""
        print("Running make setup...")
        try:
            result = subprocess.run(
                ['make', 'setup'],
                cwd=self.host_vm_dir,
                capture_output=True,
                text=True,
                timeout=300
            )

            if result.returncode == 0:
                print("✓ make setup completed")
                return True
            else:
                print(f"✗ make setup failed with code {result.returncode}")
                if result.stderr:
                    print(f"Error: {result.stderr}")
                return False

        except subprocess.TimeoutExpired:
            print("✗ make setup timed out")
            return False
        except Exception as e:
            print(f"✗ make setup error: {e}")
            return False

    def start_remote(self, vnc_display: Optional[int] = None) -> bool:
        """Start the VM with make start-remote (runs in background)."""
        print("Starting VM with make start-remote...")

        cmd = ['make', 'start-remote']
        if vnc_display is not None:
            cmd.append(f'QEMU_ARGS=-vnc :{vnc_display}')

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=self.host_vm_dir,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                proc.wait(timeout=5)
            finally:
                proc.stdout.close()
                proc.stderr.close()

            if proc.returncode != 0:
                print(f"✗ Failed to start VM (exit code: {proc.returncode})")
                return False

        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            print("✗ make start-remote timed out")
            return False
        except FileNotFoundError:
            print("✗ Make not found or host-vm directory missing")
            return False

        # Verify QEMU process is actually running
        check = subprocess.run(
            ['make', 'is-running'],
            cwd=self.host_vm_dir,
            capture_output=True,
            text=True,
        )
        if check.returncode != 0:
            print("✗ QEMU process is not running")
            return False

        print("✓ VM started")
        return True

    def wait_for_boot(self, host_ip: str, timeout: int = 120) -> bool:
        """Wait for VM to become responsive via SSH."""
        print(f"Waiting for VM to boot (timeout: {timeout}s)...")
        vm_pings = False
        vm_has_ssh = False
        start_time = time.time()

        while time.time() - start_time < timeout:
            time.sleep(2)

            # Try ping
            if not vm_pings and self._check_ping(host_ip):
                elapsed = int(time.time() - start_time)
                print(f"✓ VM responds to ping (took {elapsed}s)")
                vm_pings = True

            # Try SSH connection
            if not vm_has_ssh and self._check_ssh(host_ip):
                elapsed = int(time.time() - start_time)
                print(f"✓ VM is responsive via SSH (took {elapsed}s)")
                vm_has_ssh = True

            if vm_has_ssh and vm_pings:
                return True

        print(f"✗ VM did not become responsive within {timeout}s")
        return False

    def _check_ssh(self, host_ip: str, port: int = 22) -> bool:
        """Check if SSH port is open."""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            result = sock.connect_ex((host_ip, port))
            sock.close()
            return result == 0
        except:
            return False

    def _check_ping(self, host_ip: str) -> bool:
        """Check if host responds to ping."""
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '2', host_ip],
                capture_output=True,
                timeout=3
            )
            return result.returncode == 0
        except:
            return False

    def wait_for_bootlog_entry(self, pattern: str, timeout: int = 120) -> bool:
        """Follow the bootlog file and wait for a regex pattern to appear."""
        bootlog_path = self.host_vm_dir / "bootlog"
        regex = re.compile(pattern)
        print(f"Waiting for bootlog entry: {pattern} (timeout: {timeout}s)...")
        start_time = time.time()

        while not bootlog_path.exists():
            if time.time() - start_time >= timeout:
                print(f"✗ Bootlog file never appeared within {timeout}s")
                return False
            time.sleep(1)

        with open(bootlog_path, 'r', errors='replace') as f:
            while time.time() - start_time < timeout:
                line = f.readline()
                if line and regex.search(line):
                    elapsed = int(time.time() - start_time)
                    print(f"✓ Found bootlog entry (took {elapsed}s): {line.rstrip()}")
                    return True
                elif line:
                    continue
                else:
                    time.sleep(0.5)

        print(f"✗ Bootlog entry not found within {timeout}s")
        return False

    def collect_artifacts(self, host_ip: str, nbft_out_file: Path, dmesg_out_file: Path) -> bool:
        """SSH into the host-vm and collect intersting artifacts"""

        ssh_key = SCRIPT_DIR / ".ssh" / "id_ecdsa"
        print("Collecting artifacts from host-vm...")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            client.connect(
                host_ip,
                username='root',
                key_filename=str(ssh_key),
                timeout=5,
            )

            self.collect_ssh_artifact("NBFT", "nvme nbft show --output-format=json", client, nbft_out_file)
            self.collect_ssh_artifact("dmesg", "dmesg", client, dmesg_out_file)
            return True
        except Exception as e:
            print(f"✗ Artifacts collection failed: {e}")
            return False
        finally:
            client.close()

    def collect_ssh_artifact(self, name: str, command: str, ssh_client, output_file: Path) -> None:
        """SSH into the host-vm and export the output of a command."""

        _, stdout, stderr = ssh_client.exec_command(command, timeout=10)
        exit_status = stdout.channel.recv_exit_status()

        if exit_status != 0:
            err = stderr.read().decode().strip()
            print(f"✗ '{command}' failed (exit code: {exit_status})")
            if err:
                print(f"  {err}")
            return

        output_file.parent.mkdir(parents=True, exist_ok=True)
        with open(output_file, 'w') as f:
            f.write(stdout.read().decode())

        print(f"✓ {name} saved to {output_file}")

    def cleanup(self):
        """Kill the VM using make kill."""
        print("Cleaning up VM...")
        try:
            result = subprocess.run(
                ['make', 'kill'],
                cwd=self.host_vm_dir,
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0:
                print("✓ VM stopped")
            else:
                print(f"Note: make kill returned code {result.returncode}")

        except subprocess.TimeoutExpired:
            print("Warning: make kill timed out")
        except Exception as e:
            print(f"Warning: Error during cleanup: {e}")


# Pytest test parametrization hook
def pytest_generate_tests(metafunc):
    """Dynamically generate test parameters for each test case."""
    if metafunc.function.__name__ == 'test_boot':
        test_file = os.environ.get('TEST_CONFIG_FILE', 'tests.json')
        schema_file = os.environ.get('TEST_SCHEMA_FILE', 'schemata/tests.json')

        config = load_test_config(test_file, schema_file)

        # Generate test cases
        test_cases = []
        ids = []
        environments = config.get('environments', [])
        for env_idx, environment in enumerate(environments):
            env_name = environment.get('name', f'env{env_idx}')
            tests = environment.get('tests', [])
            for test_idx, test in enumerate(tests):
                test_name = test.get('name', f'test{test_idx}')
                test_cases.append((env_idx, test_idx))
                ids.append(f"{env_name}::{test_name}")

        if test_cases:
            metafunc.parametrize('env_idx,test_idx', test_cases, ids=ids)


# Pytest test class
class TestNVMeBoot:
    """Pytest test class for NVMe/TCP boot tests."""

    config = None
    setup_environments = set()  # Track which environments have been set up

    @classmethod
    def setup_class(cls):
        """Load configuration once for all tests."""
        test_file = os.environ.get('TEST_CONFIG_FILE', 'tests.json')
        schema_file = os.environ.get('TEST_SCHEMA_FILE', 'schemata/tests.json')
        cls.config = load_test_config(test_file, schema_file)
        ARTIFACTS_DIR.mkdir(exist_ok=True)
        print("\n" + "="*70)
        print("NVMe/TCP Boot Test Suite")
        print(f"Artifacts directory: {ARTIFACTS_DIR}")
        print("="*70)

    def test_boot(self, env_idx: int, test_idx: int):
        """Execute a single boot test."""
        environments = self.config.get('environments', [])
        if env_idx >= len(environments):
            pytest.fail("Invalid environment index")

        environment = environments[env_idx]
        env_name = environment.get('name', f'Environment {env_idx}')

        # Setup network once per environment
        if env_idx not in self.__class__.setup_environments:
            print(f"\n{'='*70}")
            print(f"Setting up environment: {env_name}")
            print(f"{'='*70}")
            try:
                # Teardown network before setting up new environment
                network_setup = NetworkSetup(environment['network'], SCRIPT_DIR)
                network_setup.teardown()

                # Setup the new environment
                prepare_environment(environment)
                self.__class__.setup_environments.add(env_idx)
            except RuntimeError as e:
                pytest.fail(f"SETUP FAILED: {e}")

        # Get the specific test
        tests = environment.get('tests', [])
        if test_idx >= len(tests):
            pytest.fail("Invalid test index")

        test = tests[test_idx]
        test_name = test.get('name', f'Test {test_idx}')
        timeout = test.get('timeout', 120)

        if timeout < 30:
            warnings.warn(f"Test '{test_name}' has a timeout of {timeout}s, which may be too low for a boot test.")

        print(f"\n{'-'*70}")
        print(f"Running: {test_name}")
        print(f"{'-'*70}")

        # Generate EFI config
        generate_test_config(test, environment)

        # Get expected host IP
        efi_gen = EFIConfigGenerator(test, environment)
        host_ip = efi_gen.get_host_ip()

        # Prepare artifacts directory
        artifact_dir = ARTIFACTS_DIR / sanitize_dir_name(test_name)
        artifact_dir.mkdir(parents=True, exist_ok=True)

        if not host_ip:
            pytest.fail("Could not determine host IP address")

        # Run the VM
        vm_runner = VMRunner(Path("host-vm"))

        try:
            # Setup VM
            if not vm_runner.setup():
                pytest.fail("VM setup failed")

            # Start VM
            vm_runner.start_remote()

            # Check bootlog for EFI boot success
            efi_pattern = r"FSOpen: Open '\\?EFI.*' Success"
            if not vm_runner.wait_for_bootlog_entry(efi_pattern, timeout):
                pytest.fail("EFI boot entry not found in bootlog")

            # Wait for boot with remaining time budget
            if not vm_runner.wait_for_boot(host_ip, timeout):
                pytest.fail(f"VM did not boot within {timeout}s")

            vm_runner.collect_artifacts(host_ip, artifact_dir / "nbft.json", artifact_dir / "dmesg")
            print(f"✓ Test passed: {test_name}")

        finally:
            # Collect artifacts
            bootlog_src = Path("host-vm") / "bootlog"
            if bootlog_src.exists():
                shutil.copy2(bootlog_src, artifact_dir / "bootlog")
                print(f"✓ Bootlog saved to {artifact_dir / 'bootlog'}")
            else:
                print(f"Warning: bootlog not found at {bootlog_src}")

            # Always cleanup
            vm_runner.cleanup()


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="NVMe/TCP Test Runner - Configure and run boot tests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run tests with pytest
  ./run_tests.py

  # Dry run (validate only)
  ./run_tests.py --dry-run

  # Pass pytest arguments
  ./run_tests.py -v -s
  ./run_tests.py --dry-run
        """
    )

    parser.add_argument(
        '-t', '--test-file',
        default='tests.json',
        help='Path to test configuration file (default: tests.json)'
    )

    parser.add_argument(
        '-s', '--schema-file',
        default='schemata/tests.json',
        help='Path to JSON schema file (default: schemata/tests.json)'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Validate configuration only, do not execute tests'
    )

    # Parse known args to separate our args from pytest args
    args, pytest_args = parser.parse_known_args()

    if not os.path.exists(args.test_file):
        print(f"Error: Test file not found: {args.test_file}")
        sys.exit(1)

    if not os.path.exists(args.schema_file):
        print(f"Error: Schema file not found: {args.schema_file}")
        sys.exit(1)

    # Set environment variables for pytest to find config
    os.environ['TEST_CONFIG_FILE'] = args.test_file
    os.environ['TEST_SCHEMA_FILE'] = args.schema_file

    try:
        if args.dry_run:
            print("Dry run mode: validating configuration only\n")
            config = load_test_config(args.test_file, args.schema_file)
            print(f"✓ Configuration is valid")
            print(f"  Environments: {len(config.get('environments', []))}")
            for env in config.get('environments', []):
                print(f"    - {env.get('name', 'Unnamed')}: {len(env.get('tests', []))} test(s)")
        else:
            # Run pytest
            pytest_args = [__file__, '-v', '--tb=short', '-s', '-rA'] + pytest_args
            sys.exit(pytest.main(pytest_args))

    except KeyboardInterrupt:
        print("\nInterrupted")
        sys.exit(130)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
