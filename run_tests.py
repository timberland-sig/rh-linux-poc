#!/usr/bin/env python3
"""
NVMe/TCP Test Runner

Reads test configurations from tests.json, validates against schema,
sets up network environments, generates EFI boot configurations,
and runs boot tests using pytest.
"""

import json
import logging
import os
import shutil
import sys
import warnings
from pathlib import Path
from typing import Dict, List, Any, Optional
import pytest

from orchestrator.eficonfig import EFIConfigGenerator
from orchestrator.utils import sanitize_dir_name
from orchestrator.netsetup import NetworkSetup
from orchestrator.runner import VMRunner

warnings.formatwarning = lambda msg, *args, **kwargs: f"Warning: {msg}\n"
logging.getLogger('paramiko').setLevel(logging.CRITICAL)


SCRIPT_DIR = Path(__file__).parent
ARTIFACTS_DIR = SCRIPT_DIR / "artifacts"
TESTS_DIR = SCRIPT_DIR / "tests"
DISPLAY_MODE_FILE = SCRIPT_DIR / ".display_mode"


def resolve_display_mode(
    cli_vnc: Optional[int] = None,
    cli_graphical: bool = False,
    env_config: Optional[Dict[str, Any]] = None,
) -> tuple:
    """Resolve display mode from CLI flags, JSON config, state file, or default.

    Returns (mode, vnc_display) where mode is 'vnc' or 'graphical',
    and vnc_display is an int or None.
    """
    if cli_graphical:
        return ('graphical', None)
    if cli_vnc is not None:
        return ('vnc', cli_vnc if cli_vnc >= 0 else None)

    if DISPLAY_MODE_FILE.exists():
        mode = DISPLAY_MODE_FILE.read_text().strip()
        if mode in ('vnc', 'graphical'):
            return (mode, None)

    if env_config is not None:
        mode = env_config.get('displayMode')
        if mode:
            vnc_display = env_config.get('vncDisplay')
            return (mode, vnc_display)

    return ('vnc', None)


def resolve_test_files(test_file_arg: Optional[str]) -> List[str]:
    """Determine which test configuration files to use.

    Priority: -t flag > tests/ directory > tests.json
    """
    if test_file_arg is not None:
        if not os.path.exists(test_file_arg):
            print(f"Error: Test file not found: {test_file_arg}")
            sys.exit(1)
        return [test_file_arg]

    if TESTS_DIR.is_dir():
        test_files = sorted(TESTS_DIR.glob("*.json"))
        if not test_files:
            print(f"Error: No JSON test files found in {TESTS_DIR}")
            sys.exit(1)
        return [str(f) for f in test_files]

    default_file = SCRIPT_DIR / "tests.json"
    if default_file.exists():
        return [str(default_file)]

    print("Error: No test configuration found.")
    print("  Provide a test file with -t, create a tests/ directory with JSON files, or create tests.json")
    sys.exit(1)


def load_merged_config(test_files: List[str], schema_file: str) -> Dict[str, Any]:
    """Load multiple test config files, validate each, and merge their environments."""
    merged_environments = []
    for test_file in test_files:
        config = load_test_config(test_file, schema_file)
        merged_environments.extend(config.get('environments', []))
    return {'environments': merged_environments}


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


def prepare_environment(environment: Dict[str, Any], display_mode: str = 'vnc', vnc_display: Optional[int] = None):
    """Setup network and target-vm for an environment."""
    network_setup = NetworkSetup(environment['network'], SCRIPT_DIR)

    network_setup.setup()
    network_setup.setup_target_vm(display_mode=display_mode, vnc_display=vnc_display)


# Pytest test parametrization hook
def pytest_generate_tests(metafunc):
    """Dynamically generate test parameters for each test case."""
    if metafunc.function.__name__ == 'test_boot':
        test_files = json.loads(os.environ.get('TEST_CONFIG_FILES', '[]'))
        schema_file = os.environ.get('TEST_SCHEMA_FILE', 'schemata/tests.json')

        config = load_merged_config(test_files, schema_file)

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
        test_files = json.loads(os.environ.get('TEST_CONFIG_FILES', '[]'))
        schema_file = os.environ.get('TEST_SCHEMA_FILE', 'schemata/tests.json')
        cls.config = load_merged_config(test_files, schema_file)
        cls.cli_vnc = json.loads(os.environ.get('TEST_CLI_VNC', 'null'))
        cls.cli_graphical = os.environ.get('TEST_CLI_GRAPHICAL', '') == '1'
        cls.no_timeout = os.environ.get('TEST_NO_TIMEOUT', '') == '1'
        ARTIFACTS_DIR.mkdir(exist_ok=True)
        print("\n" + "="*70)
        print("NVMe/TCP Boot Test Suite")
        print(f"Test files: {', '.join(test_files)}")
        print(f"Artifacts directory: {ARTIFACTS_DIR}")
        print("="*70)

    def test_boot(self, env_idx: int, test_idx: int):
        """Execute a single boot test."""
        environments = self.config.get('environments', [])
        if env_idx >= len(environments):
            pytest.fail("Invalid environment index")

        environment = environments[env_idx]
        env_name = environment.get('name', f'Environment {env_idx}')

        display_mode, vnc_display = resolve_display_mode(
            cli_vnc=self.__class__.cli_vnc,
            cli_graphical=self.__class__.cli_graphical,
            env_config=environment,
        )

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
                prepare_environment(environment, display_mode=display_mode, vnc_display=vnc_display)
                self.__class__.setup_environments.add(env_idx)
            except RuntimeError as e:
                pytest.exit(f"SETUP FAILED: {e}", returncode=1)

        # Get the specific test
        tests = environment.get('tests', [])
        if test_idx >= len(tests):
            pytest.fail("Invalid test index")

        test = tests[test_idx]
        test_name = test.get('name', f'Test {test_idx}')

        if self.__class__.no_timeout:
            timeout = float('inf')
        else:
            timeout = test.get('timeout', 120)
            if timeout < 30:
                warnings.warn(f"Test '{test_name}' has a timeout of {timeout}s, which may be too low for a boot test.")

        print(f"\n{'-'*70}")
        print(f"Running: {test_name}")
        print(f"{'-'*70}")

        # Generate EFI config and extract host IP from same instance
        efi_gen = EFIConfigGenerator(test, environment)
        efi_gen.generate()
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
            vm_runner.start_remote(display_mode=display_mode, vnc_display=vnc_display)

            # Check bootlog for EFI boot success
            efi_pattern = r"FSOpen: Open '\\?EFI.*' Success"
            if not vm_runner.wait_for_bootlog_entry(efi_pattern, timeout):
                pytest.fail("EFI boot entry not found in bootlog")

            # Wait for boot with remaining time budget
            if not vm_runner.wait_for_boot(host_ip, timeout):
                pytest.fail(f"VM did not boot within {timeout}s")

            vm_runner.collect_artifacts(host_ip, artifact_dir)
            print(f"✓ Test passed: {test_name}")

        finally:
            # Collect artifacts
            bootlog_src = Path("host-vm") / "bootlog"
            if bootlog_src.exists():
                shutil.copy2(bootlog_src, artifact_dir / "bootlog")
                print(f"✓ Bootlog saved to {artifact_dir / 'bootlog'}")
            else:
                print(f"Warning: bootlog not found at {bootlog_src}")

            eficonfig_src = Path("host-vm") / "eficonfig" / "config"
            if eficonfig_src.exists():
                shutil.copy2(eficonfig_src, artifact_dir / "eficonfig")
                print(f"✓ EFI config saved to {artifact_dir / 'eficonfig'}")
            else:
                print(f"Warning: EFI config not found at {eficonfig_src}")

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
        default=None,
        help='Path to a specific test configuration file'
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

    parser.add_argument(
        '--no-timeout',
        action='store_true',
        help='Disable test timeouts (wait indefinitely until success or manual kill)'
    )

    display_group = parser.add_mutually_exclusive_group()
    display_group.add_argument(
        '--vnc',
        nargs='?',
        type=int,
        const=-1,
        default=None,
        metavar='DISPLAY',
        help='Use VNC for VM display (optional display number, default: 0 for target, 1 for host)'
    )
    display_group.add_argument(
        '--graphical',
        action='store_true',
        help='Use graphical display (X11/Wayland)'
    )

    # Parse known args to separate our args from pytest args
    args, pytest_args = parser.parse_known_args()

    if not os.path.exists(args.schema_file):
        print(f"Error: Schema file not found: {args.schema_file}")
        sys.exit(1)

    test_files = resolve_test_files(args.test_file)

    # Set environment variables for pytest to find config
    os.environ['TEST_CONFIG_FILES'] = json.dumps(test_files)
    os.environ['TEST_SCHEMA_FILE'] = args.schema_file
    os.environ['TEST_CLI_VNC'] = json.dumps(args.vnc)
    os.environ['TEST_CLI_GRAPHICAL'] = '1' if args.graphical else ''
    os.environ['TEST_NO_TIMEOUT'] = '1' if args.no_timeout else ''

    try:
        if args.dry_run:
            print("Dry run mode: validating configuration only\n")
            config = load_merged_config(test_files, args.schema_file)
            total_envs = config.get('environments', [])
            print(f"✓ Configuration is valid ({len(test_files)} file(s), {len(total_envs)} environment(s))")
            for env in total_envs:
                print(f"  - {env.get('name', 'Unnamed')}: {len(env.get('tests', []))} test(s)")
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
