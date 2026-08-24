# Changelog

## Unreleased

### Added

- Configurable logrotate support for minion, master, API, cloud, watchdog, and exporter logs.
- Removal of the packaged `/etc/logrotate.d/salt-common` snippet once formula-managed
  rotation is enabled, so `/var/log/salt/*` is not rotated twice.
- Per-instance exporter logrotate policies and snippet filenames.
- Optional syntax validation through `file.managed.check_cmd`.
- Configurable management of exporter log directories and files.
- Explicit rendering of positive and negative logrotate boolean directives.
- Cleanup of inactive and stale formula-managed logrotate snippets.
- `pillar.reference.sls` containing the complete discoverable configuration.
- `salt:extensions:beacon_deps` - installs the third-party libraries Salt's
  beacons import but the onedir package does not vendor (`pyinotify`, `pyroute2`,
  `systemd-python`, `watchdog`, plus `pyasyncore` for the `asyncore` module
  Python 3.12 removed) into the onedir Python. `enabled` is a tri-state:
  `auto` (default) resolves per beacon from `salt:beacons` / `salt:minion:beacons`
  through `beacon_deps:beacon_map`, so a minion with no beacons installs nothing
  and no host gets the `libsystemd-dev` build toolchain unless it runs the
  `journald` beacon; `true` installs the full bundle unconditionally; `false`
  installs nothing. Beacons declared with an explicit `beacon_module` resolve to
  the underlying implementation. Packages already listed in `salt:extensions:pip`
  are not installed twice, and the apt side merges into the existing
  `build_dependencies` `pkg.installed` state.
- `tests/validate_extensions_beacon_deps.py` covering the resolution above.
- `libconfd.jinja` and `salt:config_d_preserve` / `salt:config_d_preserve_from` /
  `salt:{master,minion}_config_d_preserve` - addon drop-ins in `master.d` and
  `minion.d` are no longer deleted by the `clean: true` recurse. `_*` and
  `[0-9]*` are preserved by convention, and files named by another formula's
  own pillar (`alcali:salt_master:config_file`,
  `salt_deploy:master:config_file`, `salt:pass:master_config`) are resolved and
  preserved without any configuration under `salt:`.
- `tests/validate_config_d_preserve.py` covering the derived pattern list.

### Changed

- `master.sls`, `minion.sls` and `standalone.sls` build `exclude_pat` from
  `libconfd.jinja` instead of hardcoding `_*`. Previously any drop-in written
  by another formula was deleted on the next highstate while the state still
  reported success; the symptom always surfaced somewhere else. Existing
  behaviour is unchanged for `_*` names.
- Exporter rotation defaults to one snippet per instance.
- `pillar.example.sls` is intended as a safe practical example; the exhaustive reference is separate.
