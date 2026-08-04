# -*- coding: utf-8 -*-
# vim: ft=sls
#
# Official Salt apt repository + GPG key, for Debian 12/13 and Ubuntu 24.04+.
#
# This replaces the old pattern of hand-building a
# `deb [signed-by=...] <url> stable main` line and dearmoring the key with
# `unless: test -s <keyring-file>`. Both of those choices are where "GPG key
# pain" usually comes from:
#   * a hand-built repo line silently goes wrong whenever Salt Project
#     changes the repo layout (this has happened more than once);
#   * `unless: test -s <file>` means the key is fetched exactly once, ever
#     - if/when the upstream key is rotated, the host keeps trusting the
#     stale key forever and apt update starts failing with signature
#     errors that look nothing like "your key is old".
#
# Instead: fetch the vendor-published `.sources` file directly (so the repo
# definition can never drift from what Salt Project actually publishes),
# and re-run `gpg --dearmor` on `onchanges` so a rotated key is picked up
# automatically the next time this state runs.

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}

{%- set repo = salt_settings.pkgrepo %}
{%- set guide_ref = repo.sources_guide_ref %}
{%- if guide_ref in ('latest', '', None) %}
{%- set sources_url = 'https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.sources' %}
{%- else %}
{%- set sources_url = 'https://github.com/saltstack/salt-install-guide/releases/download/' ~ guide_ref ~ '/salt.sources' %}
{%- endif %}

{#- When `mirror_url` is set, render the .sources file locally against that
    base instead of downloading the vendor-published one. This is the escape
    hatch for upstream being unreachable - e.g. packages.broadcom.com
    handing out 401s to an anonymous/rate-limited egress IP - and for
    air-gapped or bandwidth-constrained sites generally.

    A plain apt-mirror of packages.broadcom.com republishes the dists/ tree
    unmodified, including Broadcom's own InRelease signatures, so the suite,
    components and signing key are all unchanged from upstream and only the
    host prefix differs. If you republish through something that re-signs
    (aptly, for instance), override `keyring_url` to your own key as well. -#}
{%- set mirror_url = repo.get('mirror_url', '') %}
{%- set use_mirror = mirror_url not in ('', None, False) %}

# --- clean up legacy repo/key locations from earlier formula iterations
#     (and common community tutorials) so they can't shadow or conflict
#     with the current configuration.
{%- for legacy_path in repo.get('legacy_paths', []) %}
salt-pkgrepo-remove-legacy-{{ loop.index }}:
  file.absent:
    - name: {{ legacy_path }}
{%- endfor %}

salt-pkgrepo-keyring-dir:
  file.directory:
    - name: {{ repo.keyring_dir }}
    - mode: '0755'
    - makedirs: True

salt-pkgrepo-gnupg:
  pkg.installed:
    - name: gnupg

# Download the (armored) public key. Deliberately NOT source_hash-pinned by
# default: Salt Project can rotate/re-sign this key, and pinning a static
# hash here is exactly what silently breaks installs months later once the
# upstream key content changes. Set `salt:pkgrepo:keyring_hash` in pillar
# if strict pinning is required and you're prepared to update it whenever
# upstream rotates the key.
salt-pkgrepo-fetch-key:
  file.managed:
    - name: {{ repo.keyring_armored }}
    - source: {{ repo.keyring_url }}
    - skip_verify: {{ not repo.get('keyring_hash') }}
    {%- if repo.get('keyring_hash') %}
    - source_hash: {{ repo.keyring_hash }}
    {%- endif %}
    - require:
      - file: salt-pkgrepo-keyring-dir

# gpg --dearmor is cheap and idempotent, so re-run it whenever the
# dearmored keyring is missing/empty OR older than the armored key we just
# downloaded. Deliberately NOT a bare `unless: test -s <keyring>`: that
# "locks in" the first key the host ever saw and goes stale silently on
# rotation. `file.managed` only bumps the armored file's mtime when its
# content actually changes, so the `-nt` comparison fires exactly once per
# rotation and this state is otherwise a no-op.
salt-pkgrepo-dearmor-key:
  cmd.run:
    - name: >-
        gpg --batch --yes --dearmor
        -o {{ repo.keyring_path }} {{ repo.keyring_armored }}
    - require:
      - pkg: salt-pkgrepo-gnupg
      - file: salt-pkgrepo-fetch-key
    - unless: >-
        test -s {{ repo.keyring_path }}
        && ! test {{ repo.keyring_armored }} -nt {{ repo.keyring_path }}

# The deb822 `.sources` format requires apt >= 2.4 (Debian 12+, Ubuntu
# 22.04+), which is guaranteed given this formula's supported OS list.
salt-pkgrepo-sources:
  file.managed:
    - name: {{ repo.sources_path }}
    {%- if use_mirror %}
    - source: salt://{{ tplroot }}/files/salt.sources.jinja
    - template: jinja
    - context:
        types: {{ repo.get('types', 'deb') }}
        uris: {{ mirror_url.rstrip('/') }}
        suites: {{ repo.get('suites', 'stable') }}
        components: {{ repo.get('components', 'main') }}
        signed_by: {{ repo.keyring_path }}
    {%- else %}
    - source: {{ sources_url }}
    - skip_verify: True
    {%- endif %}
    - makedirs: True
    - require:
      - cmd: salt-pkgrepo-dearmor-key
    # Order: 2, before pkg.installed states for salt-master/salt-minion/etc,
    # which don't otherwise have a require_in on this state since we don't
    # know ahead of time which of them will be used.
    - order: 2

{%- if salt_settings.pin_version %}

# Restrict apt upgrades of salt-* packages to the configured release
# series, matching Salt Project's own documented pin file name/format.
salt-pkgrepo-pin:
  file.managed:
    - name: /etc/apt/preferences.d/salt-pin-1001
    - contents: |
        # Managed by Salt - do not edit by hand.
        Package: salt-*
        Pin: version {{ salt_settings.version_series }}
        Pin-Priority: 1001
    - order: 3
{%- else %}

salt-pkgrepo-pin-absent:
  file.absent:
    - name: /etc/apt/preferences.d/salt-pin-1001
{%- endif %}
