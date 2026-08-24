#!/usr/bin/env python3
"""Validation for the config.d preserve list built by libconfd.jinja.

`clean_config_d_dir` makes `file.recurse` delete everything in master.d and
minion.d that the formula did not just write. The failure mode this guards
is silent in both directions: an addon config that is not protected is
removed while the state still reports success, and a pattern that is too
broad stops the formula from cleaning up its own stale files.

Neither shows up in a rendered-SLS smoke test, so the cases below pin the
derived list down directly.
"""
from pathlib import Path
import json

from jinja2 import Environment, FileSystemLoader, StrictUndefined

ROOT = Path(__file__).resolve().parents[1]

# The defaults the macro reads, mirrored here rather than parsed out of
# defaults.yaml: a test that reads its expectations from the file it is
# testing cannot fail when that file changes.
SETTINGS = {
    "config_path": "/etc/salt",
    "config_d_preserve": ["_*", "[0-9]*"],
    "config_d_preserve_from": [
        "alcali:salt_master:config_file",
        "salt_deploy:master:config_file",
        "salt:pass:master_config",
    ],
    "master_config_d_preserve": [],
    "minion_config_d_preserve": [],
}


def fake_salt(pillar: dict) -> dict:
    """Minimal stand-in for the `salt` dunder, supporting config.get."""

    def config_get(key, default=None):
        node = pillar
        for part in key.split(":"):
            if not isinstance(node, dict) or part not in node:
                return default
            node = node[part]
        return node

    return {"config.get": config_get}


def exclude_pat(pillar: dict, target: str, settings: dict | None = None) -> list:
    env = Environment(
        loader=FileSystemLoader(str(ROOT.parent)),
        undefined=StrictUndefined,
        extensions=["jinja2.ext.do"],
    )
    env.filters["tojson"] = json.dumps
    env.filters["unique"] = lambda value: list(dict.fromkeys(value))
    template = env.from_string(
        '{%- from "salt/libconfd.jinja" import confd_exclude_pat with context %}'
        "{{ confd_exclude_pat(settings, target) }}"
    )
    return json.loads(
        template.render(
            settings=settings or SETTINGS,
            target=target,
            salt=fake_salt(pillar),
        )
    )


def check(label: str, actual, expected) -> bool:
    ok = actual == expected
    print(f"{'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        print(f"       expected: {expected}")
        print(f"       actual:   {actual}")
    return ok


def main() -> int:
    results = []

    results.append(
        check(
            "conventional namespaces are always preserved",
            exclude_pat({}, "master"),
            ["_*", "[0-9]*"],
        )
    )

    # The point of config_d_preserve_from: configuring the addon is enough.
    results.append(
        check(
            "alcali's master config is derived from its own pillar",
            exclude_pat(
                {"alcali": {"salt_master": {"config_file": "/etc/salt/master.d/alcali.conf"}}},
                "master",
            ),
            ["_*", "[0-9]*", "alcali.conf"],
        )
    )

    results.append(
        check(
            "salt_deploy's numeric drop-in is derived as well",
            exclude_pat(
                {"salt_deploy": {"master": {"config_file": "/etc/salt/master.d/99-salt-deploy.conf"}}},
                "master",
            ),
            ["_*", "[0-9]*", "99-salt-deploy.conf"],
        )
    )

    # A master.d addon must not widen what minion.d preserves, or the minion
    # recurse silently stops cleaning a name it owns.
    results.append(
        check(
            "a master.d addon does not affect minion.d",
            exclude_pat(
                {"alcali": {"salt_master": {"config_file": "/etc/salt/master.d/alcali.conf"}}},
                "minion",
            ),
            ["_*", "[0-9]*"],
        )
    )

    results.append(
        check(
            "a path outside the config.d directory is ignored",
            exclude_pat(
                {"alcali": {"salt_master": {"config_file": "/etc/salt/alcali.conf"}}},
                "master",
            ),
            ["_*", "[0-9]*"],
        )
    )

    # exclude_pat matches a relative path, so a bare file name from a nested
    # path would protect the wrong thing.
    results.append(
        check(
            "a path in a subdirectory of config.d is ignored",
            exclude_pat(
                {"alcali": {"salt_master": {"config_file": "/etc/salt/master.d/sub/alcali.conf"}}},
                "master",
            ),
            ["_*", "[0-9]*"],
        )
    )

    results.append(
        check(
            "an unset addon key contributes nothing",
            exclude_pat({"alcali": {"salt_master": {}}}, "master"),
            ["_*", "[0-9]*"],
        )
    )

    per_target = dict(SETTINGS, master_config_d_preserve=["vendor-*.conf"])
    results.append(
        check(
            "per-target patterns are appended",
            exclude_pat({}, "master", per_target),
            ["_*", "[0-9]*", "vendor-*.conf"],
        )
    )
    results.append(
        check(
            "per-target patterns apply to that target only",
            exclude_pat({}, "minion", per_target),
            ["_*", "[0-9]*"],
        )
    )

    # A duplicate would be harmless to Salt but signals the merge order is
    # wrong, so it is worth pinning.
    results.append(
        check(
            "a name matching both a convention and an addon key appears once",
            exclude_pat(
                {"salt": {"pass": {"master_config": "/etc/salt/master.d/_pass.conf"}}},
                "master",
            ),
            ["_*", "[0-9]*", "_pass.conf"],
        )
    )

    results.append(
        check(
            "every addon key resolves together",
            exclude_pat(
                {
                    "alcali": {"salt_master": {"config_file": "/etc/salt/master.d/alcali.conf"}},
                    "salt_deploy": {"master": {"config_file": "/etc/salt/master.d/99-salt-deploy.conf"}},
                    "salt": {"pass": {"master_config": "/etc/salt/master.d/_pass.conf"}},
                },
                "master",
            ),
            ["_*", "[0-9]*", "alcali.conf", "99-salt-deploy.conf", "_pass.conf"],
        )
    )

    failed = results.count(False)
    print(f"\n{len(results) - failed}/{len(results)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
