"""Resolve ``pass:`` references during master-side Pillar decryption.

Salt 3008 removed the former built-in pass renderer.  This deliberately small
replacement supports the formula's ``decrypt_pillar`` use case and never logs
or returns credential values except as the rendered Pillar value itself.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from collections.abc import MutableMapping

from salt.exceptions import SaltRenderError

__virtualname__ = "pass"

_NAME_RE = re.compile(r"^[A-Za-z0-9._@+-]+(?:/[A-Za-z0-9._@+-]+)*$")


def __virtual__():
    if shutil.which("pass") is None:
        return False, "The 'pass' command is not installed"
    return __virtualname__


def _plain_value(value):
    """Return a wrapped Salt 3008 secret value, or None when not wrapped."""
    getter = getattr(value, "get_secret_value", None)
    if callable(getter):
        return getter()
    return None


def _fetch(reference, original):
    prefix = __opts__.get("pass_variable_prefix", "pass:")
    if not isinstance(prefix, str) or not prefix:
        raise SaltRenderError("pass_variable_prefix must be a non-empty string")
    if not reference.startswith(prefix):
        return original

    name = reference[len(prefix) :]
    if not _NAME_RE.fullmatch(name):
        raise SaltRenderError("Invalid pass credential name in Pillar")

    env = os.environ.copy()
    env["GNUPGHOME"] = str(__opts__.get("pass_gnupghome", "~/.gnupg"))
    env["PASSWORD_STORE_DIR"] = str(
        __opts__.get("pass_dir", "~/.password-store")
    )
    try:
        result = subprocess.run(
            ["pass", "show", name],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=int(__opts__.get("pass_timeout", 30)),
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SaltRenderError(f"Unable to execute pass for {name!r}") from exc

    if result.returncode:
        if __opts__.get("pass_strict_fetch", False):
            message = result.stderr.strip() or "pass command failed"
            raise SaltRenderError(f"Unable to fetch {name!r}: {message}")
        return original

    value = result.stdout.rstrip("\r\n")
    if not value and __opts__.get("pass_strict_fetch", False):
        raise SaltRenderError(f"Credential {name!r} is empty")
    return value


def _walk(value):
    if isinstance(value, MutableMapping):
        for key in list(value):
            value[key] = _walk(value[key])
        return value
    if isinstance(value, list):
        for index, item in enumerate(value):
            value[index] = _walk(item)
        return value
    if isinstance(value, tuple):
        return tuple(_walk(item) for item in value)
    if isinstance(value, str):
        return _fetch(value, value)

    plain = _plain_value(value)
    if isinstance(plain, str):
        return _fetch(plain, value)
    return value


def render(pass_info, saltenv="base", sls="", argline="", **kwargs):
    """Recursively resolve pass-prefixed values in PASS_INFO."""
    if hasattr(pass_info, "read"):
        pass_info = pass_info.read()
    return _walk(pass_info)
