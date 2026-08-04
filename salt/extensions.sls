{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}

{%- set ext = salt_settings.extensions %}
{%- set python_bin = ext.python_bin %}

# -*- coding: utf-8 -*-
# vim: ft=sls
#
# "Extra bits Salt 3008 requires": since Salt 3006, the packaged (onedir)
# salt-master/salt-minion ship and run their own bundled Python
# interpreter under /opt/saltstack/salt, completely separate from the
# system Python. `apt install python3-pygit2` or a plain `pip install
# saltext-foo` installs into the *system* Python, which the onedir
# salt-master/minion never sees - it silently behaves as if the package
# were never installed.
#
# The fix is to install extensions with pip, but pointed at the bundled
# interpreter (`salt-pip`/`bin_env: {{ python_bin }}`) instead of the
# system one. This state does that for:
#   * arbitrary pip packages (salt:extensions:pip)
#   * saltext-* Salt extensions (salt:extensions:saltext)
#   * a gitfs/git_pillar provider (salt:extensions:gitfs_provider)
#   * the beacon dependency bundle (salt:extensions:beacon_deps)
#
# Add new "extra bits" simply by adding entries to those pillar lists -
# no new states need to be written.

{%- if ext.enabled %}

{#- ------------------------------------------------------------------
    Beacon dependency resolution.

    salt:extensions:beacon_deps:enabled is a tri-state:
      true  - install the whole apt/pip bundle
      false - install nothing
      auto  - install only what this minion's configured beacons need

    Note the string comparison: YAML parses an unquoted `auto` to the
    string 'auto', but a bare `true`/`false` to a bool, so the two are
    tested separately rather than relying on truthiness (a non-empty
    string is truthy, which would make 'auto' behave as true).
    ------------------------------------------------------------------ #}
{%- set beacon_deps = ext.get('beacon_deps', {}) %}
{%- set beacon_mode = beacon_deps.get('enabled', false) %}
{%- set beacon_auto = beacon_mode is string and beacon_mode | lower == 'auto' %}
{%- set beacon_all = beacon_mode is not string and beacon_mode %}

{%- set beacon_apt = [] %}
{%- set beacon_pip_wanted = [] %}

{%- if beacon_all %}
{%-   do beacon_apt.extend(beacon_deps.get('apt', [])) %}
{%-   do beacon_pip_wanted.extend(beacon_deps.get('pip', [])) %}

{%- elif beacon_auto %}
{#-   Read the beacon pillar exactly as files/minion.d/beacons.conf does,
      so the dependency set is derived from the same data that produces
      the minion's beacon config and cannot drift from it. #}
{%-   set beacons = salt['pillar.get']('salt:beacons', {}) %}
{%-   set beacons = salt['pillar.get']('salt:minion:beacons', default=beacons, merge=True) %}
{%-   set beacon_map = beacon_deps.get('beacon_map', {}) %}

{#-   Collect the beacon *implementations* in play. Usually that is just
      the config key, but Salt allows an arbitrary key plus an explicit
      `beacon_module` entry to run several instances of one beacon
      (e.g. two `inotify` blocks under different names). Miss that and a
      renamed beacon silently loses its library. #}
{%-   set impls = [] %}
{%-   for key, conf in beacons.items() %}
{%-     if key not in impls %}
{%-       do impls.append(key) %}
{%-     endif %}
{#-     `mapping` is tested before `sequence` on purpose: Jinja's
        `sequence` test is true for a dict as well as a list, so checking
        sequence first sends the dict form down the list branch and
        iterates its keys as strings, losing beacon_module entirely. #}
{%-     if conf is mapping %}
{%-       if conf.get('beacon_module') and conf.beacon_module not in impls %}
{%-         do impls.append(conf.beacon_module) %}
{%-       endif %}
{%-     elif conf is sequence and conf is not string %}
{%-       for entry in conf %}
{%-         if entry is mapping and entry.get('beacon_module') and entry.beacon_module not in impls %}
{%-           do impls.append(entry.beacon_module) %}
{%-         endif %}
{%-       endfor %}
{%-     endif %}
{%-   endfor %}

{%-   for impl in impls %}
{%-     set needs = beacon_map.get(impl, {}) %}
{%-     for pkg_name in needs.get('apt', []) %}
{%-       if pkg_name not in beacon_apt %}
{%-         do beacon_apt.append(pkg_name) %}
{%-       endif %}
{%-     endfor %}
{%-     for pkg_name in needs.get('pip', []) %}
{%-       if pkg_name not in beacon_pip_wanted %}
{%-         do beacon_pip_wanted.append(pkg_name) %}
{%-       endif %}
{%-     endfor %}
{%-   endfor %}
{%- endif %}

{%- set beacon_enabled = beacon_all or beacon_auto %}

{#- apt-side build deps: the generic list plus, when the beacon bundle is
    on, whatever that bundle needs to compile (libsystemd-dev et al).
    Merged into one pkg.installed so a package named in both places does
    not produce two conflicting states for the same name. #}
{%- set apt_pkgs = ext.get('build_dependencies', []) | list %}
{%- for pkg_name in beacon_apt %}
{%-   if pkg_name not in apt_pkgs %}
{%-     do apt_pkgs.append(pkg_name) %}
{%-   endif %}
{%- endfor %}

{%- if apt_pkgs %}
salt-extensions-build-dependencies:
  pkg.installed:
    - pkgs: {{ apt_pkgs | tojson }}
{%- endif %}

{%- set saltext_pkgs = [] %}
{%- for name in ext.get('saltext', []) %}
{%-   if not name.startswith('saltext-') %}
{%-     do saltext_pkgs.append('saltext-' ~ name) %}
{%-   else %}
{%-     do saltext_pkgs.append(name) %}
{%-   endif %}
{%- endfor %}

{%- if saltext_pkgs %}
salt-extensions-saltext-packages:
  pip.installed:
    - pkgs: {{ saltext_pkgs | tojson }}
    - bin_env: {{ python_bin }}
    {%- if apt_pkgs %}
    - require:
      - pkg: salt-extensions-build-dependencies
    {%- endif %}
{%- endif %}

{%- if ext.get('pip', []) %}
salt-extensions-pip-packages:
  pip.installed:
    - pkgs: {{ ext.pip | tojson }}
    - bin_env: {{ python_bin }}
    {%- if apt_pkgs %}
    - require:
      - pkg: salt-extensions-build-dependencies
    {%- endif %}
{%- endif %}

{#- Beacon dependency bundle. Kept as its own state rather than folded
    into salt-extensions-pip-packages so that a failed systemd-python
    build (the one entry here that compiles C) reports against an
    obviously-named state and does not mark the operator's unrelated
    `salt:extensions:pip` list as failed too. Anything the operator
    already lists there wins and is skipped here. #}
{%- if beacon_enabled %}
{%-   set beacon_pip = [] %}
{%-   for name in beacon_pip_wanted %}
{%-     if name not in ext.get('pip', []) %}
{%-       do beacon_pip.append(name) %}
{%-     endif %}
{%-   endfor %}
{%-   if beacon_pip %}
salt-extensions-beacon-dependencies:
  pip.installed:
    - pkgs: {{ beacon_pip | tojson }}
    - bin_env: {{ python_bin }}
    {%- if apt_pkgs %}
    - require:
      - pkg: salt-extensions-build-dependencies
    {%- endif %}
{%-   endif %}
{%- endif %}

{%- if ext.get('gitfs_provider') == 'pygit2' %}
# libgit2 (the C library) still comes from apt; only the *python bindings*
# need to go into the onedir env. --no-deps avoids pip trying (and
# failing) to rebuild cffi against a different ABI than the one already
# bundled with Salt.
salt-extensions-pygit2-libgit2:
  pkg.installed:
    - name: libgit2-dev

salt-extensions-pygit2:
  pip.installed:
    - name: pygit2
    - bin_env: {{ python_bin }}
    - no_deps: True
    - require:
      - pkg: salt-extensions-pygit2-libgit2

{%- elif ext.get('gitfs_provider') == 'gitpython' %}
salt-extensions-gitpython:
  pip.installed:
    - name: GitPython
    - bin_env: {{ python_bin }}

{%- elif ext.get('gitfs_provider') == 'dulwich' %}
salt-extensions-dulwich:
  pip.installed:
    - name: dulwich
    - bin_env: {{ python_bin }}
{%- endif %}

{%- else %}

salt-extensions-disabled:
  test.show_notification:
    - text: salt:extensions:enabled is False - skipping.

{%- endif %}
