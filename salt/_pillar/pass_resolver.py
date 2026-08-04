"""Resolve every ``pass:`` reference produced by earlier external Pillars.

Configure this external Pillar after PillarStack.  It returns only top-level
subtrees containing references, with those references replaced, so ordinary
Pillar data is left untouched.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from collections.abc import Mapping

from salt.exceptions import SaltRenderError

__virtualname__ = "pass_resolver"

_NAME_RE = re.compile(r"^[A-Za-z0-9._@+-]+(?:/[A-Za-z0-9._@+-]+)*$")

_DEFAULT_PREFIX = "pass:"

# Top-level Pillar keys that configure Salt itself rather than describing a
# minion's data.  The Salt master's own options are rendered from `salt:master`
# by the `salt` formula and legitimately contain the literal prefix as the
# value of `pass_variable_prefix`; walking them would read that value as a
# reference with an empty name and fail every Pillar compilation.
_DEFAULT_SKIP_KEYS = ("salt",)


def __virtual__():
    if shutil.which("pass") is None:
        return False, "The 'pass' command is not installed"
    return __virtualname__


def _prefix():
    configured = __opts__.get("pass_variable_prefix", _DEFAULT_PREFIX)
    # An option present but unset renders as None; treat it as absent rather
    # than failing to load, which would take all Pillar compilation with it.
    if configured is None or configured == "":
        return _DEFAULT_PREFIX
    if not isinstance(configured, str):
        raise SaltRenderError(
            "pass_variable_prefix must be a string, got "
            f"{type(configured).__name__}"
        )
    return configured


def _skip_keys():
    configured = __opts__.get("pass_resolver_skip_keys", _DEFAULT_SKIP_KEYS)
    if isinstance(configured, str):
        return (configured,)
    return tuple(configured)


def _plain_value(value):
    getter = getattr(value, "get_secret_value", None)
    return getter() if callable(getter) else None


def _describe(path):
    return ":".join(str(part) for part in path) or "<root>"


def _fetch(reference, path, cache):
    prefix = _prefix()
    if not reference.startswith(prefix):
        return reference, False

    name = reference[len(prefix) :]
    if not name:
        raise SaltRenderError(
            f"Empty pass credential name at Pillar key {_describe(path)!r}; "
            f"the value is the bare prefix {prefix!r} with no name after it"
        )
    if not _NAME_RE.fullmatch(name):
        raise SaltRenderError(
            f"Invalid pass credential name {name!r} at Pillar key "
            f"{_describe(path)!r}; use slash-separated letters, numbers, dots, "
            "underscores, @, + or hyphens"
        )
    if name in cache:
        return cache[name], True

    env = os.environ.copy()
    env["GNUPGHOME"] = str(__opts__.get("pass_gnupghome", "~/.gnupg"))
    env["PASSWORD_STORE_DIR"] = str(__opts__.get("pass_dir", "~/.password-store"))
    try:
        result = subprocess.run(
            ["pass", "show", name],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=int(__opts__.get("pass_timeout", 5)),
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise SaltRenderError(
            f"Timed out fetching {name!r} for Pillar key {_describe(path)!r}; "
            "check that gpg-agent is responsive"
        ) from exc
    except (OSError, subprocess.SubprocessError) as exc:
        raise SaltRenderError(f"Unable to execute pass for {name!r}") from exc

    if result.returncode:
        message = result.stderr.strip() or "pass command failed"
        raise SaltRenderError(
            f"Unable to fetch {name!r} for Pillar key {_describe(path)!r}: "
            f"{message}"
        )
    value = result.stdout.rstrip("\r\n")
    if not value:
        raise SaltRenderError(f"Credential {name!r} is empty")
    cache[name] = value
    return value, True


def _walk(value, path, cache):
    if isinstance(value, Mapping):
        resolved = {}
        changed = False
        for key, item in value.items():
            resolved_item, item_changed = _walk(item, path + (key,), cache)
            resolved[key] = resolved_item
            changed = changed or item_changed
        return resolved, changed
    if isinstance(value, list):
        resolved = []
        changed = False
        for index, item in enumerate(value):
            resolved_item, item_changed = _walk(item, path + (index,), cache)
            resolved.append(resolved_item)
            changed = changed or item_changed
        return resolved, changed
    if isinstance(value, tuple):
        resolved, changed = _walk(list(value), path, cache)
        return tuple(resolved), changed
    if isinstance(value, str):
        return _fetch(value, path, cache)

    plain = _plain_value(value)
    if isinstance(plain, str) and plain.startswith(_prefix()):
        return _fetch(plain, path, cache)
    return value, False


def ext_pillar(minion_id, pillar, *args, **kwargs):
    """Resolve references in the Pillar accumulated before this module."""
    skip = _skip_keys()
    # One decryption per distinct credential per compilation; each fetch forks
    # pass, which forks gpg, and repeats would otherwise occupy a master worker
    # thread long enough for minions to time out.
    cache = {}
    result = {}
    for key, value in pillar.items():
        if key in skip:
            continue
        resolved, changed = _walk(value, (key,), cache)
        if changed:
            # Return the complete top-level subtree so overwrite-style merging
            # cannot discard sibling settings.
            result[key] = resolved
    return result
