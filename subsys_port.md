**New variable:** `SUBSYS_PORT` added to `defaults.sh` (line 33) with default value `4420`, overridable via `.env`.

**8 files updated across the codebase:**

| File | Change |
|------|--------|
| `defaults.sh` | Added `SUBSYS_PORT="${SUBSYS_PORT:-4420}"` |
| `.env.example` | Added `SUBSYS_PORT="4420"` with comment |
| `host-vm/Makefile` | `configure_attempt()` now uses `$SUBSYS_PORT` for the port prompt default |
| `host-vm/discover_target.sh` | `--trsvcid=4420` → `--trsvcid=$SUBSYS_PORT` (both discover commands) |
| `host-vm/gen_discovery_conf.py` | `DEFAULT_PORT` reads from `SUBSYS_PORT` env var with 4420 fallback |
| `run_tests.py` | Added `SUBSYS_PORT` to `DEFAULTS` dict; default port resolution uses it |
| `target-vm/tcp.json.in` + `target-vm/Makefile` | Templatized `"trsvcid"` as `"SUBSYS_PORT"`, added sed substitution |
| `target-vm/setup-nvme-target.sh` | Extracts port from `tcp.json` at runtime (since it runs inside the VM without access to `defaults.sh`) |
| `schemata/tests.json` | Updated description text to reference `SUBSYS_PORT` |
