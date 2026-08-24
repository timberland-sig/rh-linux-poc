import subprocess
import paramiko
import time
import re

from pathlib import Path
from typing import Optional
from scp import SCPClient

from orchestrator.utils import check_ping, check_ssh


SCRIPT_DIR = Path(__file__).parent


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

    def is_running(self) -> bool:
        """Check if the QEMU process is still running."""
        result = subprocess.run(
            ['make', 'is-running'],
            cwd=self.host_vm_dir,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip() == 'YES'

    def start_remote(self, display_mode: str = 'vnc', vnc_display: Optional[int] = None) -> bool:
        """Start the VM with make start-remote (runs in background)."""
        print("Starting VM with make start-remote...")

        cmd = ['make', 'start-remote']
        if display_mode == 'vnc':
            cmd.append(f'VNC_DISPLAY={vnc_display if vnc_display is not None else 1}')

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

        if not self.is_running():
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

            if not self.is_running():
                print("✗ QEMU process died while waiting for boot")
                return False

            # Try ping
            if not vm_pings and check_ping(host_ip):
                elapsed = int(time.time() - start_time)
                print(f"✓ VM responds to ping (took {elapsed}s)")
                vm_pings = True

            # Try SSH connection
            if not vm_has_ssh and check_ssh(host_ip):
                elapsed = int(time.time() - start_time)
                print(f"✓ VM is responsive via SSH (took {elapsed}s)")
                vm_has_ssh = True

            if vm_has_ssh and vm_pings:
                return True

        print(f"✗ VM did not become responsive within {timeout}s")
        return False

    def wait_for_bootlog_entry(self, pattern: str, timeout: int = 120) -> bool:
        """Follow the bootlog file and wait for a regex pattern to appear."""
        bootlog_path = self.host_vm_dir / "bootlog"
        regex = re.compile(pattern)
        print(f"Waiting for bootlog entry regex: R\"{pattern}\" (timeout: {timeout}s)...")
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
                    if not self.is_running():
                        print("✗ QEMU process died while waiting for bootlog entry")
                        return False
                    time.sleep(0.5)

        print(f"✗ Bootlog entry not found within {timeout}s")
        return False

    def collect_artifacts(self, host_ip: str, artifacts_dir: Path) -> bool:
        """SSH into the host-vm and collect intersting artifacts"""

        ssh_key = SCRIPT_DIR / ".." / ".ssh" / "id_ecdsa"
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

            self.collect_ssh_artifact("NBFT", "nvme nbft show --output-format=json", client, artifacts_dir / "nbft.json")
            self.collect_ssh_artifact("dmesg", "dmesg", client, artifacts_dir / "dmesg")

            self.collect_scp_artifact("NBFT raw", "/sys/firmware/acpi/tables/NBFT", client, artifacts_dir / "nbft.raw")
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

    def collect_scp_artifact(self, name: str, remote_path: str, ssh_client, output_file: Path) -> None:
        """SCP a file from the host-vm."""

        output_file.parent.mkdir(parents=True, exist_ok=True)
        output_file.unlink(missing_ok=True)
        with SCPClient(ssh_client.get_transport()) as scp:
            scp.get(remote_path, str(output_file))

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
