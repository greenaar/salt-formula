"""Manage the master's local ``pass`` credential store without revealing values.

Load this runner with ``salt-run saltutil.sync_runners``. Interactive entry
belongs in the ``salt-secret`` helper; Salt runner arguments may be persisted
in job data and must never contain credential values.
"""

from __future__ import annotations

import os
import re
import stat
import subprocess
from pathlib import Path

from salt.exceptions import CommandExecutionError

__virtualname__ = "secret_store"
__func_alias__ = {"list_": "list"}

_NAME_RE = re.compile(r"^[A-Za-z0-9._@+-]+(?:/[A-Za-z0-9._@+-]+)*$")


def __virtual__():
    return __virtualname__


def _settings():
    """Return paths from the Salt master configuration."""
    gpg_home = Path(__opts__.get("pass_gnupghome", "/etc/salt/gpgkeys"))
    store_dir = Path(__opts__.get("pass_dir", "/var/lib/salt/password-store"))
    return gpg_home, store_dir


def _validate_name(name):
    if (
        not isinstance(name, str)
        or not _NAME_RE.fullmatch(name)
        or any(component in {".", ".."} for component in name.split("/"))
    ):
        raise ValueError(
            "Invalid credential name; use slash-separated letters, numbers, "
            "dots, underscores, @, +, or hyphens"
        )
    return name


def _secret_path(name):
    _, store_dir = _settings()
    path = store_dir.joinpath(*_validate_name(name).split("/"))
    return Path(f"{path}.gpg")


def _run_pass(args, stdin=None):
    gpg_home, store_dir = _settings()
    env = os.environ.copy()
    env["GNUPGHOME"] = str(gpg_home)
    env["PASSWORD_STORE_DIR"] = str(store_dir)
    try:
        return subprocess.run(
            ["pass", *args],
            input=stdin,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            check=True,
        )
    except FileNotFoundError as exc:
        raise CommandExecutionError("The 'pass' command is not installed") from exc
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.strip() or "pass command failed"
        raise CommandExecutionError(message) from exc


def list_(prefix=None):
    """List credential names, never their values."""
    _, store_dir = _settings()
    if prefix:
        _validate_name(prefix)
    if not store_dir.is_dir():
        return []

    names = []
    for path in store_dir.rglob("*.gpg"):
        if ".git" in path.parts:
            continue
        name = path.relative_to(store_dir).as_posix()[:-4]
        if prefix is None or name == prefix or name.startswith(prefix + "/"):
            names.append(name)
    return sorted(names)


def exists(name):
    """Return whether NAME exists without decrypting it."""
    return _secret_path(name).is_file()


def generate(name, length=32, overwrite=False, symbols=False):
    """Generate a credential without returning its value."""
    name = _validate_name(name)
    length = int(length)
    if not 1 <= length <= 4096:
        raise ValueError("length must be between 1 and 4096")
    if exists(name) and not overwrite:
        return {"name": name, "changed": False, "comment": "already exists"}

    args = ["generate"]
    if overwrite:
        args.append("--force")
    if not symbols:
        args.append("--no-symbols")
    args.extend([name, str(length)])
    _run_pass(args)
    return {"name": name, "changed": True}


def import_file(name, source, overwrite=False):
    """Import a protected file on the master without returning its contents."""
    name = _validate_name(name)
    source_path = Path(source)
    if not source_path.is_absolute():
        raise ValueError("source must be an absolute path on the Salt master")
    source_stat = source_path.stat()
    if not stat.S_ISREG(source_stat.st_mode):
        raise ValueError("source must be a regular file")
    if source_stat.st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise ValueError("source must not be accessible by group or other users")
    if exists(name) and not overwrite:
        return {"name": name, "changed": False, "comment": "already exists"}

    value = source_path.read_text(encoding="utf-8").rstrip("\r\n")
    if not value:
        raise ValueError("source is empty")
    args = ["insert", "--multiline"]
    if overwrite:
        args.append("--force")
    args.append(name)
    _run_pass(args, stdin=value + "\n")
    return {"name": name, "changed": True}


def remove(name, confirm=False):
    """Remove NAME only when ``confirm=True`` is supplied."""
    name = _validate_name(name)
    if not confirm:
        return {
            "name": name,
            "changed": False,
            "comment": "refusing removal without confirm=True",
        }
    if not exists(name):
        return {"name": name, "changed": False, "comment": "not found"}
    _run_pass(["rm", "--force", name])
    return {"name": name, "changed": True}
