# -*- coding: utf-8 -*-
# vim: ft=yaml
---
# Safe, practical example pillar for the salt formula.
#
# Copy only the sections required by the target host. See pillar.reference.sls
# for every supported option and README.md for deployment patterns.

salt:
  version: ''
  pin_version: true
  version_series: '3008.*'

  # Managed minion example. Remove this block on a master-only host.
  minion:
    master: salt.example.org
    master_type: str

  # Uncomment to configure a master.
  # master:
  #   interface: 0.0.0.0
  #   file_roots:
  #     base:
  #       - /srv/salt
  #   pillar_roots:
  #     base:
  #       - /srv/pillar

  # Logrotate is deliberately opt-in. Component defaults cover the standard
  # Salt log paths; override paths if Salt writes elsewhere.
  logrotate:
    enabled: false
    validate: true
    cleanup: true
    # components:
    #   minion:
    #     rotate: 14
    #     maxsize: 250M
    #   api:
    #     enabled: true
    #   cloud:
    #     enabled: true

  # Optional Prometheus exporter. It is normally used on a salt-master.
  exporter:
    enabled: false
    version: ''
    instances:
      default:
        listen_address: 127.0.0.1:2112
        config:
          listen_address: 127.0.0.1:2112
          telemetry_path: /metrics
          log_level: info
        # Setting log_file enables file logging and per-instance rotation.
        # log_file: /var/log/salt-exporter/default.log
        # logrotate:
        #   rotate: 14
        #   maxsize: 100M

  extensions:
    enabled: true
    pip: []
    saltext: []
    gitfs_provider: ''
    # auto (default) installs only the libraries this minion's configured
    # beacons need - nothing at all if no beacons are set. Safe formula-wide;
    # 'true' forces the full bundle including a compiler toolchain. Do not
    # also apt-install python3-pyinotify / python3-pyroute2: those land in
    # the system python, which the onedir minion never imports.
    beacon_deps:
      enabled: auto

  # pass-backed credential store, master-only. Register the resolver under
  # `salt:master` above, after PillarStack:
  #
  #   salt:
  #     master:
  #       ext_pillar:
  #         - stack: /srv/salt/pillarstack/stack.cfg
  #         - pass_resolver: {}
  #
  # Do not put pass_dir / pass_gnupghome / pass_strict_fetch / pass_timeout
  # under `salt:master`. salt.pass writes them to master.d/_pass.conf: the
  # resolver runs during pillar compilation, so pillar-derived config is
  # circular and unrecoverable if pillar ever stops compiling.
  #
  # Never set pass_variable_prefix in pillar: the resolver walks every
  # string in compiled pillar, so the literal 'pass:' is read as a
  # reference with an empty name and breaks pillar compilation.
  pass:
    enabled: false
    # Must match <store_dir>/.gpg-id on an existing store.
    gpg_identity: Salt Master Secrets <salt-master@example.net>

  minion_watchdog:
    enabled: false
