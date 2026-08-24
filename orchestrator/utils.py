import paramiko
import re
import subprocess

from pathlib import Path


SCRIPT_DIR = Path(__file__).parent


def cidr_to_netmask(cidr: int) -> str:
    """Convert CIDR prefix length to dotted decimal netmask."""
    mask = (0xffffffff >> (32 - cidr)) << (32 - cidr)
    return f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"


def netmask_to_cidr(netmask: str) -> int:
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


def sanitize_dir_name(name: str) -> str:
    """Convert a test name to a short, terminal-friendly directory name."""
    name = name.lower()
    name = re.sub(r'[^a-z0-9]+', '-', name)
    name = name.strip('-')
    return name


def check_ssh(host: str, port: int = 22) -> bool:
    """Check if SSH connection, authentication, and channel execution succeed."""
    ssh_key = SCRIPT_DIR / ".." / ".ssh" / "id_ecdsa"
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            host,
            port=port,
            username='root',
            key_filename=str(ssh_key),
            timeout=5,
            banner_timeout=5,
            auth_timeout=5,
        )
        _, stdout, _ = client.exec_command("true", timeout=5)
        stdout.channel.recv_exit_status()
        return True
    except:
        return False
    finally:
        client.close()


def check_ping(host_ip: str) -> bool:
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