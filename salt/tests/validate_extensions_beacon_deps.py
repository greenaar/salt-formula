#!/usr/bin/env python3
"""Validation for salt:extensions:beacon_deps resolution in extensions.sls.

Renders extensions.sls against a synthetic pillar and asserts on the state
IDs and package lists produced. The `auto` mode reads the beacon pillar and
maps beacon names to libraries, so the interesting failures are silent ones:
a beacon whose library is not installed still renders valid SLS, it just
never fires at runtime. These cases pin that mapping down.
"""
from pathlib import Path
import copy

import yaml
from jinja2 import Environment, BaseLoader

ROOT = Path(__file__).resolve().parents[1]


def build_body() -> str:
    """extensions.sls minus its map.jinja import, which needs a live minion.

    map.jinja merges defaults/osmap/pillar via Salt execution modules that do
    not exist outside a minion process. Stripping the import and injecting
    `ext` directly keeps this runnable as a plain unit test.
    """
    src = (ROOT / "extensions.sls").read_text()
    keep = [
        line
        for line in src.splitlines()
        if "map.jinja" not in line
        and "tpldir" not in line
        and "set ext =" not in line
        and "set python_bin" not in line
    ]
    return "{%- set python_bin = ext.python_bin %}\n" + "\n".join(keep)


def fake_salt(pillar: dict) -> dict:
    """Minimal stand-in for the `salt` dunder, supporting pillar.get."""

    def pillar_get(key, default=None, merge=False):
        node = pillar
        for part in key.split(":"):
            if not isinstance(node, dict) or part not in node:
                return default
            node = node[part]
        if merge and isinstance(default, dict) and isinstance(node, dict):
            merged = dict(default)
            merged.update(node)
            return merged
        return node

    return {"pillar.get": pillar_get}


def render(body, ext, beacon_pillar=None):
    env = Environment(loader=BaseLoader(), extensions=["jinja2.ext.do"])
    pillar = {"salt": dict(beacon_pillar or {})}
    out = env.from_string(body).render(ext=ext, salt=fake_salt(pillar))
    return yaml.safe_load(out) or {}


def pkgs(parsed, state_id, fn):
    if state_id not in parsed:
        return None
    for args in parsed[state_id][fn]:
        if "pkgs" in args:
            return args["pkgs"]
    return None


BEACON_PIP = "salt-extensions-beacon-dependencies"
BUILD_DEPS = "salt-extensions-build-dependencies"


def main() -> None:
    body = build_body()
    defaults = yaml.safe_load((ROOT / "defaults.yaml").read_text())["salt"]

    def ext(**overrides):
        base = copy.deepcopy(defaults["extensions"])
        base.update(overrides)
        return base

    def bd(**overrides):
        base = copy.deepcopy(defaults["extensions"]["beacon_deps"])
        base.update(overrides)
        return base

    # auto mode installs nothing on a minion with no beacons - notably no
    # compiler toolchain, which is the whole point of auto over true.
    parsed = render(body, ext(), None)
    assert BEACON_PIP not in parsed, "auto mode installed deps with no beacons"
    assert BUILD_DEPS not in parsed, "auto mode installed a toolchain with no beacons"

    # inotify pulls pyasyncore too (stdlib asyncore removed in 3.12) but
    # must NOT drag in the journald toolchain.
    parsed = render(body, ext(), {"beacons": {"inotify": {"/etc/salt": {}}}})
    assert pkgs(parsed, BEACON_PIP, "pip.installed") == ["pyinotify", "pyasyncore"]
    assert BUILD_DEPS not in parsed, "inotify should not require a compiler"

    # journald is the only mapped beacon that compiles C.
    parsed = render(body, ext(), {"beacons": {"journald": {"services": {}}}})
    assert pkgs(parsed, BEACON_PIP, "pip.installed") == ["systemd-python"]
    assert "libsystemd-dev" in pkgs(parsed, BUILD_DEPS, "pkg.installed")

    # An arbitrary config key plus beacon_module must resolve to the real
    # implementation, in both the dict and the list config forms. Jinja's
    # `sequence` test is true for dicts, so the dict form regresses easily.
    for conf in ({"beacon_module": "journald"}, [{"beacon_module": "journald"}]):
        parsed = render(body, ext(), {"beacons": {"renamed": conf}})
        assert pkgs(parsed, BEACON_PIP, "pip.installed") == ["systemd-python"], (
            f"beacon_module not resolved for config form {type(conf).__name__}"
        )

    # Beacons covered by the bundled psutil need nothing.
    parsed = render(body, ext(), {"beacons": {"load": {"averages": {}}}})
    assert BEACON_PIP not in parsed, "unmapped beacon should contribute nothing"

    # salt:minion:beacons merges over salt:beacons, same as beacons.conf.
    parsed = render(
        body, ext(), {"beacons": {"inotify": {}}, "minion": {"beacons": {"journald": {}}}}
    )
    assert set(pkgs(parsed, BEACON_PIP, "pip.installed")) == {
        "pyinotify",
        "pyasyncore",
        "systemd-python",
    }

    # Anything the operator already lists in extensions:pip wins.
    parsed = render(
        body,
        ext(pip=["pyroute2"]),
        {"beacons": {"network_settings": {}, "inotify": {}}},
    )
    assert "pyroute2" not in pkgs(parsed, BEACON_PIP, "pip.installed")

    # enabled: true is unconditional and ignores the beacon pillar.
    parsed = render(body, ext(beacon_deps=bd(enabled=True)), None)
    assert pkgs(parsed, BEACON_PIP, "pip.installed") == defaults["extensions"][
        "beacon_deps"
    ]["pip"]

    # enabled: false installs nothing even with beacons configured. Guards
    # against 'auto' being read as a truthy string somewhere.
    parsed = render(body, ext(beacon_deps=bd(enabled=False)), {"beacons": {"journald": {}}})
    assert BEACON_PIP not in parsed
    assert BUILD_DEPS not in parsed

    # A pillar predating this feature must not error on the missing key.
    legacy = {
        "enabled": True,
        "python_bin": "/opt/saltstack/salt/bin/python3",
        "build_dependencies": [],
        "pip": ["PyMySQL"],
        "saltext": [],
        "gitfs_provider": "",
    }
    parsed = render(body, legacy, {"beacons": {"journald": {}}})
    assert BEACON_PIP not in parsed, "legacy pillar should opt out silently"

    # beacon apt deps merge into the existing build_dependencies state
    # rather than declaring a second pkg.installed.
    parsed = render(
        body,
        ext(build_dependencies=["libgit2-dev"]),
        {"beacons": {"journald": {}}},
    )
    merged = pkgs(parsed, BUILD_DEPS, "pkg.installed")
    assert merged[0] == "libgit2-dev" and "libsystemd-dev" in merged

    # Whole state off.
    parsed = render(body, ext(enabled=False), {"beacons": {"journald": {}}})
    assert "salt-extensions-disabled" in parsed

    print("extensions beacon_deps: all cases passed")


if __name__ == "__main__":
    main()
