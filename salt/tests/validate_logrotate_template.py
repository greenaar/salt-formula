#!/usr/bin/env python3
"""Lightweight validation for the shared logrotate Jinja template."""
from pathlib import Path
import subprocess
import tempfile

from jinja2 import Environment, FileSystemLoader, StrictUndefined

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise RuntimeError(message)


def main() -> None:
    env = Environment(
        loader=FileSystemLoader(ROOT / "logrotate" / "files"),
        extensions=["jinja2.ext.do"],
        undefined=StrictUndefined,
    )
    env.globals["raise"] = fail
    template = env.get_template("component.jinja")
    settings = {
        "filename": "salt-minion",
        "paths": ["/var/log/salt/minion"],
        "frequency": "daily",
        "rotate": 14,
        "maxage": None,
        "size": "",
        "minsize": "",
        "maxsize": "250M",
        "missingok": True,
        "notifempty": True,
        "compress": True,
        "delaycompress": True,
        "dateext": False,
        "dateformat": "",
        "copytruncate": True,
        "sharedscripts": False,
        "create": "",
        "su": "root root",
        "olddir": "",
        "prerotate": "",
        "postrotate": "",
        "firstaction": "",
        "lastaction": "",
        "extra_directives": [],
    }
    rendered = template.render(
        tplroot="salt", component="minion", settings=settings
    )
    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        handle.write(rendered)
        candidate = handle.name
    result = subprocess.run(
        ["/usr/sbin/logrotate", "--debug", candidate],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(result.stderr)

    invalid_cases = (
        {"paths": []},
        {"frequency": "fortnightly"},
        {"size": "1M", "maxsize": "2M"},
        {"filename": "../unsafe"},
    )
    for changes in invalid_cases:
        candidate_settings = settings.copy()
        candidate_settings.update(changes)
        try:
            template.render(
                tplroot="salt", component="invalid", settings=candidate_settings
            )
        except RuntimeError:
            continue
        raise AssertionError(f"Invalid settings rendered successfully: {changes}")


if __name__ == "__main__":
    main()
