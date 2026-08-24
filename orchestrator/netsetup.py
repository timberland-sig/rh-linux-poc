import os
import subprocess
import time

from dotenv import dotenv_values
from pathlib import Path
from typing import Dict, List, Any, Optional

from orchestrator.defaults import DEFAULTS
from orchestrator.utils import netmask_to_cidr, check_ssh


SCRIPT_DIR = Path(__file__).parent


class NetworkSetup:
    """Handles network bridge setup and target-vm startup."""

    def __init__(self, network_config: Dict[str, Any], script_dir: Path):
        self.network_config = network_config
        self.script_dir = script_dir
        self.target_vm_dir = script_dir / "target-vm"

    def _build_setup_args(self) -> List[str]:
        """Build command line arguments for ./setup.sh net."""
        args = []

        for bridge in ['br0', 'br1', 'br2']:
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
                    prefix_length = netmask_to_cidr(subnet_mask)
                else:
                    # It's already a CIDR prefix length
                    prefix_length = int(subnet_mask)

                hypervisor_ip = f"{hypervisor_ip}/{prefix_length}"

            args.append(slave)
            args.append(hypervisor_ip)

        return args

    def _check_target_vm_disk(self) -> bool:
        """Check if target-vm disk exists and has non-zero size."""
        disk_path = self.target_vm_dir / "disks" / "boot.qcow2"

        if not disk_path.exists():
            print(f"✗ Target VM disk not found: {disk_path}")
            print("  Please set up the target-vm first by running:")
            print("    cd target-vm && make auto-install")
            return False

        try:
            disk_size = disk_path.stat().st_size
            if disk_size == 0:
                print(f"✗ Target VM disk is empty: {disk_path}")
                print("  Please set up the target-vm first by running:")
                print("    cd target-vm && make auto-install")
                return False

            print(f"✓ Target VM disk found: {disk_path} ({disk_size / (1024**3):.2f} GB)")
            return True
        except Exception as e:
            print(f"✗ Error checking target VM disk: {e}")
            return False

    def _load_target_cidr_env(self) -> Dict[str, str]:
        """Build environment variables for TARGET_CIDR from network config."""
        env = os.environ.copy()
        env.update(dotenv_values(SCRIPT_DIR / ".env"))
        env['_DEFAULTS_SKIP_ENV'] = '1'
        env['TARGET_CIDR2'] = f"{DEFAULTS['TARGET_IP2']}/{DEFAULTS['SUBNET']}"
        env['TARGET_CIDR3'] = f"{DEFAULTS['TARGET_IP3']}/{DEFAULTS['SUBNET']}"

        # Extract target IPs and subnet masks from network config
        for bridge_name, bridge_key in [('br1', 'br1'), ('br2', 'br2')]:
            if bridge_key not in self.network_config:
                continue

            bridge_config = self.network_config[bridge_key]
            target_ip = bridge_config.get('targetVmIp', '')
            subnet_mask = bridge_config.get('subnetMask', 24)

            if len(target_ip) == 0 or target_ip == "dhcp":
                continue

            # Ensure we have CIDR notation
            if '/' not in target_ip:
                if isinstance(subnet_mask, str) and '.' in subnet_mask:
                    # Convert dotted decimal to CIDR
                    prefix_length = netmask_to_cidr(subnet_mask)
                else:
                    prefix_length = int(subnet_mask)
                target_cidr = f"{target_ip}/{prefix_length}"
            else:
                target_cidr = target_ip

            # Set TARGET_IP2 for br1, TARGET_IP3 for br2
            if bridge_key == 'br1':
                env['TARGET_CIDR2'] = target_cidr
            elif bridge_key == 'br2':
                env['TARGET_CIDR3'] = target_cidr

        return env

    def _get_target_vm_host(self) -> str:
        """Get the target VM's reachable IP from the network config (br0)."""
        br0 = self.network_config.get('br0', {})
        target_ip = br0.get('targetVmIp', '')
        if target_ip:
            return target_ip.split('/')[0]
        return DEFAULTS.get('TARGET_IP2', '192.168.101.20')

    def setup_target_vm(self, display_mode: str = 'vnc', vnc_display: Optional[int] = None,
                        use_router: bool = False):
        """Setup and start the target-vm."""
        print("\n" + "="*70)
        print("Setting up target-vm")
        print("="*70)

        # Check disk exists
        if not self._check_target_vm_disk():
            raise RuntimeError("Target VM disk not ready")

        # Prepare environment with TARGET_CIDR variables
        env = self._load_target_cidr_env()

        # Build vm.sh command with display mode
        cmd = ['bash', './vm.sh', 'start', 'disks/boot.qcow2']
        if display_mode == 'graphical':
            cmd.append('--graphical')
        elif display_mode == 'vnc':
            cmd.append(f'--vnc={vnc_display if vnc_display is not None else 0}')

        # Start target-vm with ./vm.sh
        # Use Popen + wait() instead of subprocess.run() with capture_output,
        # because the backgrounded QEMU process inherits the pipes and prevents
        # communicate() from returning even after make itself exits.
        print(f"Starting target-vm with '{' '.join(cmd)}'...")
        try:
            proc = subprocess.Popen(
                cmd,
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
            print("✗ 'make auto-start' timed out")
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
        if result.stdout.strip() != 'YES':
            print("✗ QEMU process is not running")
            raise RuntimeError("Target-vm QEMU process failed to start")
        print("✓ Target-vm started")

        # Wait for target-vm SSH to become available
        br0_slave = self.network_config.get('br0', {}).get('slave', 'none')
        target_host = self._get_target_vm_host() if use_router and br0_slave != 'none' else 'localhost'
        target_port = DEFAULTS['TARGET_PORT'] if target_host == 'localhost' else 22

        print(f"Waiting for target-vm SSH on {target_host}...")
        ssh_timeout = 60
        start_time = time.time()
        while time.time() - start_time < ssh_timeout:
            if check_ssh(target_host, target_port):
                elapsed = int(time.time() - start_time)
                print(f"✓ Target-vm SSH is ready (took {elapsed}s)")
                break
            time.sleep(2)
        else:
            raise RuntimeError(f"Target-vm SSH not available within {ssh_timeout}s")

        # Run netsetup.sh with timeout
        print(f"Configuring target-vm network with './netsetup.sh {target_host}'...")
        netsetup_script = self.script_dir / "target-vm" / "netsetup.sh"

        try:
            result = subprocess.run(
                [str(netsetup_script), target_host],
                cwd=self.target_vm_dir,
                env=env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=120
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
        for i, bridge in enumerate(['br0', 'br1', 'br2']):
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

    def setup_router(self):
        """Provision and start the virtual router using ./setup.sh router."""
        setup_script = self.script_dir / "setup.sh"
        cmd = [str(setup_script), 'router']

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
                print("✓ Router setup completed successfully")
            else:
                print(f"✗ Router setup failed with code {result.returncode}")
                if result.stderr:
                    print(f"Error:\n{result.stderr}")
                raise RuntimeError(f"Router setup failed with exit code {result.returncode}")
        except subprocess.TimeoutExpired:
            print("✗ Router setup timed out after 5 minutes")
            raise RuntimeError("Router setup timed out after 5 minutes")
        except FileNotFoundError:
            print(f"✗ Setup script not found: {setup_script}")
            raise RuntimeError(f"Setup script not found: {setup_script}")

    def teardown_router(self):
        """Tear down the virtual router using ./teardown.sh router."""
        teardown_script = self.script_dir / "teardown.sh"
        cmd = [str(teardown_script), 'router']

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
                print("✓ Router teardown completed successfully")
            else:
                print(f"✗ Router teardown failed with code {result.returncode}")
                if result.stderr:
                    print(f"Error:\n{result.stderr}")
                raise RuntimeError(f"Router teardown failed with exit code {result.returncode}")
        except subprocess.TimeoutExpired:
            print("✗ Router teardown timed out")
            raise RuntimeError("Router teardown timed out")
        except FileNotFoundError:
            print(f"✗ Teardown script not found: {teardown_script}")
            raise RuntimeError(f"Teardown script not found: {teardown_script}")
