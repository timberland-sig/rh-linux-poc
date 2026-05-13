#!/usr/bin/env python3
"""
Generate a discovery.conf from test configuration JSON files.

Reads the same test config files as run_tests.py, extracts all unique
NVMe/TCP targets from boot attempts, and writes a discovery.conf file
that nvme-cli can use for discovery.
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional


SCRIPT_DIR = Path(__file__).parent.parent
TESTS_DIR = SCRIPT_DIR / "tests"

DEFAULTS = {
    'TARGET_IP2': '192.168.101.20',
    'TARGET_IP3': '192.168.110.20',
}

DEFAULT_PORT = 4420


def resolve_test_files(test_file_arg: Optional[str]) -> List[str]:
    if test_file_arg is not None:
        if not os.path.exists(test_file_arg):
            print(f"Error: Test file not found: {test_file_arg}", file=sys.stderr)
            sys.exit(1)
        return [test_file_arg]

    if TESTS_DIR.is_dir():
        test_files = sorted(TESTS_DIR.glob("*.json"))
        if test_files:
            return [str(f) for f in test_files]

    default_file = SCRIPT_DIR / "tests.json"
    if default_file.exists():
        return [str(default_file)]

    print("Error: No test configuration found.", file=sys.stderr)
    sys.exit(1)


def load_configs(test_files: List[str]) -> List[Dict[str, Any]]:
    configs = []
    for path in test_files:
        with open(path) as f:
            configs.append(json.load(f))
    return configs


def resolve_target_ip(attempt: Dict[str, Any], attempt_idx: int, environment: Dict[str, Any]) -> str:
    target_ip = attempt.get('targetIp', 'default')
    if target_ip != 'default':
        return target_ip.split('/')[0]

    network = environment.get('network', {})
    if attempt_idx == 0:
        ip = network.get('virbr1', {}).get('targetVmIp', '')
        return ip.split('/')[0] if ip else DEFAULTS['TARGET_IP2']
    elif attempt_idx == 1:
        ip = network.get('virbr2', {}).get('targetVmIp', '')
        return ip.split('/')[0] if ip else DEFAULTS['TARGET_IP3']
    return DEFAULTS['TARGET_IP2']


def resolve_port(attempt: Dict[str, Any]) -> int:
    port = attempt.get('port', 'default')
    if port == 'default':
        return DEFAULT_PORT
    return int(port)


def collect_targets(configs: List[Dict[str, Any]]) -> List[tuple]:
    seen = set()
    group_order = []
    group_map = {}

    for config in configs:
        for environment in config.get('environments', []):
            for test in environment.get('tests', []):
                for idx, attempt in enumerate(test.get('bootAttempts', [])):
                    target_name = attempt.get('targetName', '')
                    ip = resolve_target_ip(attempt, idx, environment)
                    port = resolve_port(attempt)
                    key = (ip, port)
                    if key not in seen:
                        seen.add(key)
                        if target_name not in group_map:
                            group_map[target_name] = []
                            group_order.append(target_name)
                        group_map[target_name].append(key)

    return [(name, group_map[name]) for name in group_order]


def write_discovery_conf(groups: List[tuple], output_path: Path):
    total = sum(len(targets) for _, targets in groups)
    with open(output_path, 'w') as f:
        for i, (name, targets) in enumerate(groups):
            if i > 0:
                f.write("\n")
            if len(name) > 0:
                f.write(f"# {name}\n")
            for ip, port in targets:
                f.write(f"--transport=tcp --trsvcid={port} --traddr={ip}\n")

    print(f"Wrote {total} target(s) to {output_path}")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Generate discovery.conf from test configuration")
    parser.add_argument('-t', '--test-file', default=None, help='Path to a specific test configuration file')
    parser.add_argument('-o', '--output', default=None, help='Output path (default: host-vm/.build/discovery.conf)')
    args = parser.parse_args()

    test_files = resolve_test_files(args.test_file)
    configs = load_configs(test_files)
    groups = collect_targets(configs)

    if not groups:
        print("No NVMe/TCP targets found in configuration.", file=sys.stderr)
        sys.exit(1)

    output_path = Path(args.output) if args.output else Path(__file__).parent / ".build" / "discovery.conf"
    write_discovery_conf(groups, output_path)


if __name__ == '__main__':
    main()
