{#-
  salt.exporter.install
  ---------------------------------------------------------------------------
  Downloads the requested release into Salt's cache dir, verifies it against
  the release's published checksums.txt, and only then flips a symlink at
  <install_dir>/salt-exporter to the newly extracted (versioned) binary.

  Idempotency / upgrade model:
    - archive.extracted is keyed on the *destination directory*, which
      is namespaced by version (.../salt-exporter/<version>/). A new
      version = a new directory = a real re-download. An unchanged
      version = archive.extracted sees the target already populated and
      does nothing (no network call, no re-extraction).
    - The binary is installed as <install_dir>/salt-exporter-<version>,
      never overwritten in place.
    - <install_dir>/salt-exporter is a symlink that gets repointed with
      file.symlink (force: True). Salt's symlink management replaces the
      link via create-then-rename, so a state run interrupted mid-way
      still leaves either the old or the new fully-formed symlink in
      place - never a half-written binary. Rolling back a bad release is
      then just: point salt:exporter:version back at the previous
      version and re-run - the old versioned binary is still on disk
      unless you've pruned it (see the cleanup state below, disabled by
      default).
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/exporter/map.jinja" import se with context %}

include:
  - {{ tplroot }}.exporter.user

salt-exporter-cache-dir:
  file.directory:
    - name: {{ se.cachedir }}
    - makedirs: True
    - user: root
    - group: root
    - mode: '0755'

salt-exporter-extract-{{ se.version }}:
  archive.extracted:
    - name: {{ se.extract_dir }}
    - source: {{ se.download_url }}
    {%- if se.verify_checksum %}
    - source_hash: {{ se.checksums_url }}
    {%- else %}
    - skip_verify: True
    {%- endif %}
    - archive_format: tar
    - enforce_toplevel: False
    - keep_source: False
    - if_missing: {{ se.extract_dir }}/salt-exporter
    - require:
      - file: salt-exporter-cache-dir

{#- Install both shipped binaries (salt-exporter + the salt-live TUI) at a
    versioned path. Only salt-exporter is symlinked/serviced; salt-live is
    an interactive operator tool, installed for convenience. #}
salt-exporter-versioned-binary:
  file.managed:
    - name: {{ se.versioned_binary }}
    - source: {{ se.extract_dir }}/salt-exporter
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - archive: salt-exporter-extract-{{ se.version }}

salt-live-versioned-binary:
  file.managed:
    - name: {{ se.install_dir }}/salt-live-{{ se.version }}
    - source: {{ se.extract_dir }}/salt-live
    - user: root
    - group: root
    - mode: '0755'
    - require:
      - archive: salt-exporter-extract-{{ se.version }}

{#- Atomic upgrade: repoint the stable symlink at the newly-installed
    versioned binary. `force: True` lets Salt replace an existing
    symlink (or a stale regular file) safely. #}
salt-exporter-symlink:
  file.symlink:
    - name: {{ se.symlink }}
    - target: {{ se.versioned_binary }}
    - force: True
    - require:
      - file: salt-exporter-versioned-binary

salt-live-symlink:
  file.symlink:
    - name: {{ se.install_dir }}/salt-live
    - target: {{ se.install_dir }}/salt-live-{{ se.version }}
    - force: True
    - require:
      - file: salt-live-versioned-binary

{#- Optional housekeeping: prune old versioned binaries once the symlink
    has moved on. Off by default - flip salt:exporter:prune_old_versions
    to True once you're comfortable losing the instant-rollback safety
    net described above. #}
{%- if se.prune_old_versions %}
salt-exporter-prune-old-versions:
  cmd.run:
    - name: >
        find {{ se.install_dir }} -maxdepth 1
        \( -name 'salt-exporter-*' -o -name 'salt-live-*' \)
        ! -name 'salt-exporter-{{ se.version }}'
        ! -name 'salt-live-{{ se.version }}'
        -type f -delete
    - onchanges:
      - file: salt-exporter-symlink
      - file: salt-live-symlink
{%- endif %}
