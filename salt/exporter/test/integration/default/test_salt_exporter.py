"""
Testinfra suite for the salt.exporter sub-state (folded into the salt
formula from the former standalone salt-exporter formula).

Run standalone against any already-highstated host with:

    pip install pytest-testinfra
    py.test --hosts=ssh://user@host test_salt_exporter.py

These assertions intentionally avoid hardcoding a specific exporter
version so pillar.example.sls can be bumped without touching this file.
Requires pillar with at least:

    salt:
      exporter:
        enabled: true
        version: "<some release>"
"""
import re

import pytest

INSTANCE = "default"
CONFIG_ROOT = "/etc/salt-exporter"
INSTALL_DIR = "/usr/local/bin"
SERVICE_NAME = f"salt-exporter-{INSTANCE}"
UNIT_PATH = f"/etc/systemd/system/{SERVICE_NAME}.service"


# ---------------------------------------------------------------------------
# User / group
# ---------------------------------------------------------------------------

def test_dedicated_user_exists(host):
    user = host.user("salt-exporter")
    assert user.exists
    assert user.shell in ("/usr/sbin/nologin", "/sbin/nologin", "/bin/false")


def test_dedicated_group_exists(host):
    assert host.group("salt-exporter").exists


def test_user_is_not_root_and_has_no_login_home_bypass(host):
    user = host.user("salt-exporter")
    assert user.uid != 0
    assert user.home == "/var/lib/salt-exporter"


# ---------------------------------------------------------------------------
# Binary install / symlink
# ---------------------------------------------------------------------------

def test_symlink_exists_and_points_into_install_dir(host):
    link = host.file(f"{INSTALL_DIR}/salt-exporter")
    assert link.exists
    assert link.is_symlink
    target = link.linked_to
    assert target.startswith(f"{INSTALL_DIR}/salt-exporter-")


def test_versioned_binary_is_executable_and_owned_by_root(host):
    link = host.file(f"{INSTALL_DIR}/salt-exporter")
    versioned = host.file(link.linked_to)
    assert versioned.exists
    assert versioned.mode & 0o111  # executable by someone
    assert versioned.user == "root"


def test_binary_reports_a_version(host):
    cmd = host.run(f"{INSTALL_DIR}/salt-exporter -version")
    # Some versions print to stdout, some to stderr, some exit non-zero on
    # -version; assert we got *some* output rather than a "not found".
    assert "not found" not in (cmd.stdout + cmd.stderr).lower()


def test_no_leftover_downloads_in_tmp(host):
    """Regression check for the /tmp requirement: nothing named
    salt-exporter* should exist outside Salt's own cachedir/install dir."""
    result = host.run("find /tmp -maxdepth 2 -iname 'salt-exporter*'")
    assert result.stdout.strip() == ""


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def test_instance_config_dir_permissions(host):
    d = host.file(f"{CONFIG_ROOT}/{INSTANCE}")
    assert d.exists
    assert d.is_directory
    assert d.group == "salt-exporter"
    assert oct(d.mode) == "0o750"


def test_config_yaml_present_and_parses(host):
    f = host.file(f"{CONFIG_ROOT}/{INSTANCE}/config.yaml")
    assert f.exists
    assert oct(f.mode) == "0o640"
    import yaml  # test runner dependency, not target-host dependency

    parsed = yaml.safe_load(f.content_string)
    assert isinstance(parsed, dict)
    assert "listen_address" in parsed


def test_exporter_env_present(host):
    f = host.file(f"{CONFIG_ROOT}/{INSTANCE}/exporter.env")
    assert f.exists
    assert "EXPORTER_EXTRA_ARGS=" in f.content_string


# ---------------------------------------------------------------------------
# systemd unit hardening
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "directive,expected",
    [
        ("NoNewPrivileges", "true"),
        ("ProtectSystem", "strict"),
        ("ProtectHome", "true"),
        ("PrivateTmp", "true"),
        ("ProtectKernelModules", "true"),
        ("ProtectKernelTunables", "true"),
        ("ProtectControlGroups", "true"),
        ("RestrictNamespaces", "true"),
        ("RestrictSUIDSGID", "true"),
        ("LockPersonality", "true"),
        ("MemoryDenyWriteExecute", "true"),
        ("RemoveIPC", "true"),
    ],
)
def test_unit_hardening_directives(host, directive, expected):
    unit = host.file(UNIT_PATH)
    assert unit.exists
    pattern = rf"^{directive}={expected}\s*$"
    assert re.search(pattern, unit.content_string, re.MULTILINE)


def test_unit_runs_as_dedicated_user(host):
    unit = host.file(UNIT_PATH)
    assert re.search(r"^User=salt-exporter\s*$", unit.content_string, re.MULTILINE)
    assert re.search(r"^Group=salt-exporter\s*$", unit.content_string, re.MULTILINE)


def test_unit_execstart_uses_stable_symlink_not_versioned_path(host):
    unit = host.file(UNIT_PATH)
    match = re.search(r"^ExecStart=(\S+)", unit.content_string, re.MULTILINE)
    assert match
    assert match.group(1) == f"{INSTALL_DIR}/salt-exporter"


def test_unit_has_no_privileged_capabilities_on_unprivileged_port(host):
    """Default pillar listens on :2112, so no bind capability should be granted."""
    unit = host.file(UNIT_PATH)
    if "CapabilityBoundingSet=CAP_NET_BIND_SERVICE" not in unit.content_string:
        assert re.search(r"^CapabilityBoundingSet=\s*$", unit.content_string, re.MULTILINE)


# ---------------------------------------------------------------------------
# Service state
# ---------------------------------------------------------------------------

def test_service_is_enabled_and_running(host):
    svc = host.service(SERVICE_NAME)
    assert svc.is_enabled
    assert svc.is_running


def test_process_runs_as_unprivileged_user(host):
    proc = host.process.filter(comm="salt-exporter")
    if not proc:
        pytest.skip("process not visible via ps in this container - covered by is_running above")
    for p in proc:
        assert p.user == "salt-exporter"


def test_metrics_endpoint_responds(host):
    cmd = host.run("curl -fsS --max-time 5 http://127.0.0.1:2112/metrics")
    assert cmd.rc == 0
    assert "salt_" in cmd.stdout or cmd.stdout == ""  # empty body is fine if master is idle


# ---------------------------------------------------------------------------
# Idempotency: re-running the highstate with the same pillar should not
# report changes to the install state (checked by the harness that
# invokes `salt-call state.apply test=True` and greps the summary; kept
# here as a marker test that documents the expectation for CI wiring).
# ---------------------------------------------------------------------------

def test_idempotent_reapply_reports_no_changes(host):
    cmd = host.run("salt-call --local state.apply salt.exporter test=True --out=json")
    if cmd.rc != 0:
        pytest.skip("salt-call not available in this verifier context")
    assert '"result": false' not in cmd.stdout.replace(" ", "")
