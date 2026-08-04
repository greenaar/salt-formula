# -*- coding: utf-8 -*-
# vim: ft=yaml
#
# Example pillar for the `salt` formula. Copy the bits you need into your
# own pillar tree (e.g. pillar/salt/master.sls) - this file intentionally
# shows a master + api + a few extras all at once; a minion-only host would
# use a much smaller subset (see the "Minion-only host" example at the
# bottom).
#
# Everything under `salt:` merges over defaults.yaml; anything you don't
# set here keeps the formula's default. Native master/minion options are
# passed through, so this file illustrates common settings rather than every
# option supported by Salt itself.
---
salt:

  # ---------------------------------------------------------------------
  # Core / Package Version Management
  # ---------------------------------------------------------------------
  # version: ''            # Exact Salt version to install (e.g. '3008.2'); empty = latest available
  # pin_version: true      # Pin apt to the version_series below; false = allow any version
  # version_series: '3008.*'  # APT pin regex (default)
  # install_packages: true   # Install salt packages via pkg.installed (false = config-only)
  # use_pip: false           # Also install apache-libcloud for salt-cloud via pip

  # ---------------------------------------------------------------------
  # Master Configuration
  # ---------------------------------------------------------------------
  # `salt:master` keys are written verbatim into /etc/salt/master.d/defaults.conf
  # (anything not listed explicitly here falls back to Salt's own built-in
  # default - see files/master.d/defaults.conf for the full reference, ~1850 lines).
  master:
    # Primary settings
    interface: 0.0.0.0
    worker_threads: 5          # Min 3; increase if master seems slow on returns
    publish_port: 4505         # ZeroMQ publisher port
    ret_port: 4506             # Return/authentication port
    pidfile: /var/run/salt-master.pid
    pki_dir: /etc/salt/pki/master
    cachedir: /var/cache/salt/master
    sock_dir: /var/run/salt/master
    user: root

    # Large-scale tuning
    max_open_files: 100000     # Min per minion (at least 1 FD); raise for large estates
    loop_interval: 60          # Maintenance cycle in seconds
    keep_jobs: 24              # Hours to keep job cache
    timeout: 5                 # Default salt-cli timeout
    output: nested             # Default CLI output format

    # File Server backends and roots
    file_roots:
      base:
        - /srv/salt
    pillar_roots:
      base:
        - /srv/pillar
    fileserver_backend:
      - roots
      - git                    # Add 'git' to enable git fileserver; configure gitfs_remotes below
    top_file_merging_strategy: merge   # merge | same (last env wins)
    env_order: ['base', 'dev', 'prod']  # Environment ordering for merge strategy
    hash_type: md5             # Hash type for file server (sha256 recommended for new setups)

    # Git File Server (gitfs) - requires extensions.gitfs_provider
    gitfs_provider: pygit2
    gitfs_remotes:
      - https://github.com/example-org/salt-states.git
      # Per-remote options supported:
      # - https://github.com/other/repo:
      #     env: prod
      #     root: salt/prod
    gitfs_env_whitelist:       # Only these branches/tags become fileserver environments
      - base
      - v*
    # gitfs_env_blacklist:     # Exclude these from environments
    #   - staging
    gitfs_ssl_verify: True
    # gitfs_user: 'git'        # HTTPS auth username
    # gitfs_password: ''        # HTTPS auth password

    # Pillar backends
    ext_pillar:
      - cmd_yaml: echo '{}'    # Example placeholder; replace with real external pillars
    # ext_pillar:
    #   - hiera: /etc/hiera.yaml
    #   - vault:               # SaltStack Vault pillar
    #       host: https://vault.example.com
    #       token: '${VAULT_TOKEN}'
    pillar_source_merging_strategy: smart  # recurse | aggregate | overwrite | smart
    pillar_safe_render_error: True
    # pillar_opts: False        # Include master config in minion pillar (security risk)

    # Git External Pillar (git_pillar)
    # git_pillar_provider: pygit2
    # git_pillar_remotes:
    #   - https://github.com/example-org/salt-pillars.git
    # git_pillar_root: pillar   # Subdirectory containing pillar top file + SLS files

    # Security settings
    auto_accept: False         # Never use in production
    permissive_pki_access: False
    rotate_aes_key: True
    token_expire: 43200        # Salt API token lifetime (12 hours)
    # open_mode: False         # Insecure - no key exchange; only for highly secure networks

    # Publisher ACLs (who can run what on minions)
    # publisher_acl:
    #   deployer:
    #     - test.ping
    #     - state.highstate
    #     - cmd.run|re:^(ls|df)$  # restricted commands via regex
    # publisher_acl_blacklist:
    #   users:
    #     - untrusted_user
    #   modules:
    #     - cmd
    client_acl_verify: True

    # External Auth (PAM-based REST API auth)
    # external_auth:
    #   pam:
    #     saltadmin:
    #       - '.*'               # All modules/functions
    #       - '@wheel'            # All wheel commands
    #       - '@runner'           # All runner commands
    #       - '@job':             # Job management
    #           - '*': [list_jobs, get_jid]

    # LDAP authentication (master-to-minion auth)
    # auth.ldap.server: 'ldap://ldap.example.com'
    # auth.ldap.port: 389
    # auth.ldap.basedn: 'dc=example,dc=com'
    # auth.ldap.binddn: 'cn=salt,ou=svc,dc=example,dc=com'
    # auth.ldap.bindpw: 'secret'
    # auth.ldap.filter: 'uid={{ username }}'

    # Event management
    max_event_size: 1048576     # Max event message size in bytes (1MB)
    ping_on_rotate: False       # Ping minions after AES key rotation
    preserve_minion_cache: False

    # Job cache tuning for large deployments
    job_cache: True
    minion_data_cache: True
    # cache: localfs            # localfs | mysql | postgres | mongodb
    # memcache_expire_seconds: 0  # Memcached expiration (set if using memcache)
    # con_cache: False          # Cache connected minion IDs for max_minions performance

    # Syndic settings (if this master has child syndics below it)
    # order_masters: False      # Set True if running child masters below
    # syndic_master: 'topmaster.example.org'  # If running as a syndic itself

    # Peer Publish (minion-to-minion command execution)
    # peer:
    #   '*.web.*':
    #     - test.ping
    #     - state.highstate
    # peer_run:
    #   'admin.example.org':
    #     - manage.up

    # State system settings
    state_top: top.sls
    renderer: yaml_jinja
    failhard: False
    state_verbose: True
    state_output: full          # full | terse | mixed | changes
    # env_order: ['base', 'dev', 'prod']
    master_tops: {}            # External node classifier integration (e.g., hiera, puppet)

    # Salt-SSH settings
    roster_file: /etc/salt/roster
    ssh_log_file: /var/log/salt/ssh
    # ssh_minion_opts:
    #   gpg_keydir: /root/gpg
    # ssh_use_home_key: False

    # REST API (salt-api) settings - populated via salt:api below
    rest_cherrypy: {}          # See salt.api section

    # SSL/TLS for master-minion communication
    # ssl:
    #   keyfile: /etc/ssl/salt/master.key
    #   certfile: /etc/ssl/salt/master.crt
    #   ssl_version: PROTOCOL_TLSv1_2

  # ---------------------------------------------------------------------
  # Log rotation (api, cloud, exporter, master, minion, watchdog)
  # ---------------------------------------------------------------------
  logrotate:
    enabled: true                 # Global switch; false removes managed snippets
    package: logrotate
    config_dir: /etc/logrotate.d
    # Removed once `enabled` and `cleanup` are both true: the distro
    # salt-common snippet rotates /var/log/salt/* wholesale and would
    # otherwise double-rotate the paths managed below. Set to '' to keep it.
    salt_common_filename: salt-common
    components:
      minion:
        enabled: true
        filename: salt-minion     # /etc/logrotate.d/<filename>
        paths:
          - /var/log/salt/minion
        frequency: daily          # hourly | daily | weekly | monthly | yearly
        rotate: 14
        maxage: 90                # null disables the directive
        size: ''                  # e.g. 100M; normally use only one size directive
        minsize: ''
        maxsize: 250M
        missingok: true
        notifempty: true
        compress: true
        delaycompress: true
        dateext: true
        dateformat: '-%Y%m%d'
        copytruncate: true        # avoids needing to signal/restart the daemon
        sharedscripts: false
        create: ''                # e.g. '0640 root root'; blank omits it
        su: root root
        olddir: ''
        prerotate: ''
        postrotate: ''
        firstaction: ''
        lastaction: ''
        extra_directives: []      # raw directives, e.g. ['extension .log']
      master:
        enabled: true
        filename: salt-master
        paths:
          - /var/log/salt/master
        frequency: daily
        rotate: 14
        maxsize: 250M
      api:
        enabled: true
        filename: salt-api
        paths:
          - /var/log/salt/api
        frequency: daily
        rotate: 14
        maxsize: 250M
      cloud:
        enabled: true
        filename: salt-cloud
        paths:
          - /var/log/salt/cloud
        frequency: weekly
        rotate: 8
      watchdog:
        enabled: true
        filename: salt-watchdog
        # Leave paths empty to track salt:minion_watchdog:log_file, which
        # is where the watchdog cron actually writes. Only applied when
        # salt:minion_watchdog:enabled is true.
        paths: []
        frequency: weekly
        rotate: 8
      exporter:
        enabled: true
        filename: salt-exporter
        frequency: daily
        rotate: 14
        # Exporter paths are collected from each enabled instance's log_file.

  # ---------------------------------------------------------------------
  # salt-exporter (https://kpetremann.github.io/salt-exporter/) - a
  # Prometheus exporter for salt-master job/event metrics. Master-only:
  # only installs when `salt:master` above is populated AND enabled here.
  # Downloads a versioned, checksum-verified release into a dedicated
  # hardened systemd unit.
  # ---------------------------------------------------------------------
  exporter:
    enabled: true
    version: "0.13.0"            # required once enabled - release tag, no leading 'v'

    # Internal mirror (override to bypass GitHub):
    # release_base_url: https://internal-artifacts.example.com/salt-exporter
    # download_url_override: ''      # Exact archive URL bypassing the template
    # checksums_url_override: ''     # Exact checksums URL bypassing the template

    prometheus:
      enabled: true
      labels:
        job: salt-exporter
        env: production
        role: salt-master

    instances:
      default:
        listen_address: "0.0.0.0:2112"
        config:
          listen_address: "0.0.0.0:2112"
          telemetry_path: "/metrics"
          log_level: "info"
          metrics:
            salt_responses_total:
              enabled: true
            salt_function_status:
              enabled: true
              filters:
                functions:
                  - "state.highstate"
                  - "state.sls"
                  - "cmd.run"
                states: []

    # User/account for the exporter service
    user: salt-exporter
    group: salt-exporter
    manage_user: true
    install_dir: /usr/local/bin
    config_dir: /etc/salt-exporter
    home_dir: /var/lib/salt-exporter
    prune_old_versions: false

    # Systemd hardening overrides (empty = use defaults)
    service:
      hardening_overrides: {}
      # ProtectSystem: strict
      # ProtectHome: true
      # NoNewPrivileges: true
      # CapabilityBoundingSet: ''     # Empty unless port < 1024
      # RestrictNamespaces: true

    # Optional firewall rules (ufw or firewalld) per instance
    firewall:
      enabled: false
      backend: ufw                 # ufw | firewalld
      source: ''                   # CIDR; empty = allow from anywhere
      zone: public                 # firewalld only

  # ---------------------------------------------------------------------
  # salt-api (rest_cherrypy), enables SaltGUI below to talk to the master
  # ---------------------------------------------------------------------
  api:
    rest_cherrypy:
      port: 8000
      host: 127.0.0.1
      disable_ssl: true          # Put behind nginx TLS terminator in production
      collect_stats: false
    external_auth:
      pam:
        saltadmin:
          - '.*'                   # All module functions
          - '@wheel'               # All wheel commands
          - '@runner'              # All runner commands

  # ---------------------------------------------------------------------
  # Minion (the master's own minion, if it runs one)
  # ---------------------------------------------------------------------
  minion:
    master: salt.example.org     # Can be a list for multi-master
    master_type: str             # str = all masters hot; failover = sequential
                                 # disable = running without master connection
    # master_shuffle: False       # Randomize master order (use with master_type: failover)
    # random_master: True         # Connect to any master in the list randomly

    # Connection tuning
    auth_tries: 7                # Auth attempts before giving up
    auth_timeout: 60             # Seconds to wait for master response
    master_alive_interval: 30    # Check master health every N seconds (failover mode)
    ping_interval: 0             # Ping master every N minutes (0 = disabled)
    recon_default: 100           # Min reconnect delay ms
    recon_max: 5000              # Max reconnect delay ms
    recon_randomize: True        # Add random jitter to reconnect delays

    # Grains
    grains:
      role: webserver
      datacenter: dc1
    grains_refresh_every: 1      # Refresh every N minutes (0 = disabled)
    grains_cache: False          # Cache grains on minion (may contain sensitive data)

    # Logging
    log_file: /var/log/salt/minion
    log_level: warning           # garbage | trace | debug | info | warning | error | critical
    log_fmt_console: '[%(levelname)-8s] %(message)s'
    log_fmt_logfile: '%(asctime)s,%(msecs)03.0f [%(name)-17s][%(levelname)-8s] %(message)s'
    # log_granular_levels:       # Fine-grained log level control per module
    #   salt.config: warning
    #   salt.loaded.ext.module.cmdmod: debug

    # Module management
    disable_modules: []          # Block specific modules on minions
    # whitelist_modules:         # Only allow these (complements disable_modules)
    #   - test
    #   - pkg
    module_dirs: []              # Extra directories to search for modules
    providers: {}                # Override default module provider (e.g., pkg: yumpkg5)

    # State execution
    startup_states: ''           # highstate | sls | top | '' (none)
    # sls_list:                   # If startup_states=sls, these states run at boot
    #   - edit.vim
    state_top: top.sls
    renderer: yaml_jinja         # yaml_jinja | json_jinja | yaml_mako | etc.
    failhard: False              # Stop state execution on first failure
    state_verbose: True
    state_output: full           # full | terse | mixed | changes

    # File client (remote = uses master's fileserver; local = masterless)
    # file_client: remote        # Set to 'local' for masterless operation

    # Beacon configuration
    beacons:
      cert_info:
        - files:
            - /etc/ssl/certs/mycert.pem
          notify_days: 30        # Warn if cert expires within N days
        - interval: 86400        # Check every N seconds (default beacon check interval)

    # Engine configuration (event pipeline plugins)
    # engines:
    #   - logstats:
    #       intervals:
    #         publish: 300
    #         job_returns: 300

    # Reactor (event-driven state execution)
    # reactor:
    #   salt/minion/start/*/start:
    #     - /srv/reactor/on_minion_start.sls

    # Returners (where to send command results)
    # return:                     # Multiple returners supported
    #   - mysql
    #   - redis

    # Custom minion modules (loaded from master's extension_modules)
    # extension_modules: /srv/salt/extmodules

    # File recv settings
    file_recv: False             # Never allow minions to push files to master
    file_recv_max_size: 100      # Max file size in MB that can be pushed

    # TCP keepalive
    tcp_keepalive: True
    tcp_keepalive_idle: 300      # First keepalive after 5 minutes
    # tcp_keepalive_cnt: -1       # OS default probes
    # tcp_keepalive_intvl: -1     # OS default interval

  # Minion Watchdog config (cron-driven crash/hang recovery)
  minion_watchdog:
    enabled: true
    script_path: /usr/local/bin/salt-minion-watchdog.sh
    log_file: /var/log/salt-minion-watchdog.log
    minion_log_file: /var/log/salt/minion
    state_dir: /var/run/salt-minion-watchdog
    service_name: salt-minion
    min_restart_interval: 60   # Minimum seconds between restarts

    # Cron schedule (every 5 minutes)
    cron:
      enabled: true
      user: root
      minute: '*/5'
      hour: '*'
      daymonth: '*'
      month: '*'
      dayweek: '*'
      identifier: SALT_MINION_WATCHDOG

    # Detection threshold (treat minion as hung if no log writes in this many minutes)
    stale_minutes: 15

    # Additional error strings to scan for in minion logs
    extra_error_patterns:
      - "AuthenticationError"
      - "Unable to connect"

    # Restart circuit breaker
    circuit_breaker:
      max_restarts: 5          # Alert instead of restart after this many in window
      window_seconds: 7200     # Rolling window (2 hours)

    # Alert command when circuit breaker opens
    # alert_cmd: >-
    #   curl -s -X POST -H 'Content-type: application/json'
    #   --data "{\"text\": \"$WATCHDOG_ALERT_MSG\"}"
    #   https://hooks.example.com/services/T000/B000/XXXX

  # ---------------------------------------------------------------------
  # Extra bits Salt 3008 (onedir) needs: extensions/gitfs providers get
  # installed into the bundled onedir python, not the system one.
  # ---------------------------------------------------------------------
  extensions:
    enabled: true                # Default; false = skip entirely
    gitfs_provider: pygit2       # pygit2 | gitpython | dulwich | '' (off)
    saltext:                     # saltext-* packages ('saltext-' prefix auto-added)
      - saltext-kubernetes
      - saltext-mysql
      - proxmox                  # Becomes 'saltext-proxmox' automatically
    pip:                         # Arbitrary python packages for bundled Python
      - PyMySQL
    build_dependencies: []       # apt packages needed (e.g. libgit2-dev for pygit2)
    # Beacon dependency bundle. Salt's beacons import third-party
    # libraries that the onedir package does not vendor; without these a
    # configured beacon silently never fires.
    beacon_deps:
      # auto (default) - resolve per beacon from salt:beacons /
      #   salt:minion:beacons through beacon_map; nothing if no beacons.
      # true  - install the apt+pip lists below unconditionally.
      # false - install nothing.
      enabled: auto
      apt:                       # Used only when enabled is true
        - build-essential
        - libsystemd-dev
        - pkg-config
      pip:                       # Used only when enabled is true
        - pyinotify
        - pyasyncore
        - pyroute2
        - systemd-python
        - watchdog
      # Used in auto mode. Merged over the defaults, so adding a custom
      # beacon here keeps the built-in entries. Unlisted beacons need
      # nothing (psutil, which onedir bundles, covers status/load/
      # memusage/swapusage/diskusage/service/sh).
      beacon_map:
        inotify:
          pip:
            - pyinotify
            - pyasyncore         # stdlib `asyncore` pyinotify imports, gone in py3.12
        network_settings:
          pip:
            - pyroute2
        network_info:
          pip:
            - pyroute2
        journald:
          apt:                   # Only mapped beacon needing a compiler
            - build-essential
            - libsystemd-dev
            - pkg-config
          pip:
            - systemd-python
        watchdog:
          pip:
            - watchdog
        telegram_bot_msg:
          pip:
            - python-telegram-bot
        twilio_txt_msg:
          pip:
            - twilio
        napalm:
          pip:
            - napalm

  # ---------------------------------------------------------------------
  # SaltGUI (https://github.com/erwindon/SaltGUI) - web interface
  # ---------------------------------------------------------------------
  saltgui:
    enabled: true
    method: archive              # archive (pinned tarball, recommended) or git
    version: '1.33.0'            # SaltGUI release tag - no 'v' prefix!
    ref: master                  # Git branch/tag when method=git
    repo: https://github.com/erwindon/SaltGUI.git
    target: /srv/saltgui         # Where to install SaltGUI
    user: root                   # Owner of installed files
    group: root

    nginx:                       # Optional reverse proxy vhost
      enabled: true
      server_name: salt.example.org
      listen: 80
      api_backend: http://127.0.0.1:8000  # salt-api rest_cherrypy endpoint

  # ---------------------------------------------------------------------
  # salt-ssh roster (writes /etc/salt/roster)
  # ---------------------------------------------------------------------
  ssh_roster:
    web01:
      host: 10.0.0.11
      user: root
      port: 22
      priv: /etc/salt/pki/ssh/salt-ssh.rsa
      timeout: 30                # SSH connection timeout in seconds
    web02:
      host: 10.0.0.12
      user: deploy
      minion_opts:
        user: deploy
    db01:
      host: 10.0.0.20
      user: root
      host_key_checks: false     # Skip strict host key checking (use carefully)

  # ---------------------------------------------------------------------
  # salt-cloud (cloud provisioning)
  # ---------------------------------------------------------------------
  cloud:
    template_sources:
      providers: salt://salt/files/cloud.providers.d
      profiles: salt://salt/files/cloud.profiles.d
      maps: salt://salt/files/cloud.maps.d
    # Profile and provider definitions go in pillar as:
    # cloud:
    #   profiles:
    #     ec2-us-east:
    #       provider: my-ec2-config
    #       size: t3.micro
    #       image: ami-xxxxx
    #       minion:
    #         master: salt.example.org
    #   providers:
    #     my-ec2-config:
    #       driver: ec2
    #       id: AKIAIOSFODNN7EXAMPLE
    #       key: your-aws-key-here
    #       region: us-east-1

  # ---------------------------------------------------------------------
  # GitFS key management (for authenticated gitfs/git_pillar remotes)
  # ---------------------------------------------------------------------
  gitfs:
    keys:
      salt-states:
        pub: |                   # SSH public key content
          ssh-ed25519 AAAAC3Nza...
        priv: |                  # SSH private key content (base64 or literal)
          -----BEGIN OPENSSH PRIVATE KEY-----
          ...

  # ---------------------------------------------------------------------
  # Third-party formulas pulled in via git (top-level pillar key, not under salt:)
  # ---------------------------------------------------------------------
  # salt_formulas:
  #   list:
  #     base:
  #       - nginx-formula
  #       - postgres-formula:
  #           rev: v1.4.0


# =====================================================================
# ALTERNATE DEPLOYMENT EXAMPLES
# =====================================================================
# These blocks are commented so this file remains one valid pillar document.
# Copy one into a separate pillar SLS and uncomment it.

# Minion-only host (no master/api/saltgui/exporter)
# -------------------------------------------------
# salt:
#   minion:
#     master: salt.example.org
#     master_type: str
#     log_level: warning
#
#   minion_watchdog:
#     enabled: true
#     cron:
#       minute: '*/5'
#
#   logrotate:
#     enabled: true
#     components:
#       minion:
#         rotate: 14
#         maxsize: 250M
#
#   extensions:
#     enabled: true
#     gitfs_provider: ''
#     saltext: []
#     pip: []

# Multi-master minion with failover
# ---------------------------------
# salt:
#   minion:
#     master:
#       - salt-master-01.example.org
#       - salt-master-02.example.org
#     master_type: failover
#     master_shuffle: true
#     master_alive_interval: 30
#     random_reauth_delay: 60

# Masterless minion
# -----------------
# Omit master_type so init.sls selects salt.standalone.
# salt:
#   minion:
#     file_client: local
#     startup_states: highstate
#     file_roots:
#       base:
#         - /srv/salt
#     pillar_roots:
#       base:
#         - /srv/pillar

# Syndic
# ------
# salt:
#   master:
#     order_masters: true
#   syndic:
#     syndic_master: top-master.example.org
#     syndic_master_port: 4506

# Multiple exporter instances
# ---------------------------
# salt:
#   master:
#     interface: 0.0.0.0
#   exporter:
#     enabled: true
#     version: '0.13.0'
#     instances:
#       local:
#         listen_address: 127.0.0.1:2112
#         config:
#           listen_address: 127.0.0.1:2112
#           telemetry_path: /metrics
#           log_level: info
#       prometheus:
#         listen_address: 0.0.0.0:9212
#         log_file: /var/log/salt-exporter/prometheus.log
#         config:
#           listen_address: 0.0.0.0:9212
#           telemetry_path: /metrics
#           log_level: warning
#   logrotate:
#     enabled: true
#     components:
#       exporter:
#         rotate: 14
#         maxsize: 100M
