# salt formula

Installs and configures Salt itself (master, minion, api, syndic, cloud,
ssh) plus a few operational extras (extensions, SaltGUI, a Prometheus
exporter, a minion watchdog, custom modules/states/beacons). Refactored
to target a small, current OS/Salt matrix instead of trying to support
everything Salt has ever run on.

## Contents

- [Scope](#scope)
- [Quickstart](#quickstart)
- [Architecture Overview](#architecture-overview)
- [Common deployment examples](#common-deployment-examples)
- [Logrotate configuration reference](#logrotate-configuration-reference)
- [Sub-states Reference](#sub-states-reference)
- [Migrating](#migrating-from-the-old-ad-hoc-saltmastersls)
- [Verifying a run](#verifying-a-run)
- [Troubleshooting](#troubleshooting)
- [File Layout Reference](#file-layout-reference)


## Scope

- **OS**: Debian 12 (bookworm), Debian 13 (trixie), Ubuntu 24.04+ (noble
  and later). Everything is gated on `grains.os_family == 'Debian'`; any
  other OS gets a loud `test.fail_without_changes` instead of a silent
  partial apply (see `unsupported.sls`).
- **Salt**: 3008 (onedir/LTS) and later. Older non-onedir Salt (pre-3006)
  is not supported - this formula assumes the bundled-Python packaging
  model throughout (see "Extensions" below).

If you need RedHat/SUSE/FreeBSD/macOS/Windows/legacy-Salt support, use the
upstream community `salt-formula-salt` instead; this is a deliberately
narrower fork/rewrite for a Debian/Ubuntu-only estate.

## Quickstart

```yaml
# pillar/salt/master.sls
salt:
  master:
    file_roots:
      base:
        - /srv/salt
    pillar_roots:
      base:
        - /srv/pillar
```

```yaml
# top.sls
base:
  'salt-master-host':
    - salt
```

Use `pillar.example` as a safe starting point. `pillar.reference.sls` is the exhaustive, commented configuration reference.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          init.sls                                │
│  ┌───────┐ ─include→ ┌──────────┐                               │
│  │pkgrepo│           │salt-forms│ (third-party formulas)       │
│  └───┬───┘           └──────────┘                               │
│      │                                                         │
│  gates on pillar keys:                                         │
│  ├─ salt.master    → salt.master, salt.exporter                │
│  ├─ salt.cloud     → salt.cloud                                │
│  ├─ salt.ssh_roster→ salt.ssh                                   │
│  ├─ salt.minion+   → salt.minion (with master_type)            │
│  │  master_type    →                                          │
│  ├─ salt.minion    → salt.standalone (masterless, no          │
│  │  absent         master_type set)                             │
│  ├─ salt.minion+   → salt.minion_watchdog                      │
│  │  +watchdog      →                                            │
│  ├─ salt.api       → salt.api (includes salt.master first)     │
│  ├─ salt.syndic    → salt.syndic (includes salt.master first)  │
│  ├─ extensions     → salt.extensions                           │
│  ├─ saltgui        → salt.saltgui                               │
│  └─ sync           → salt.sync                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Layout / what gets included

`init.sls` includes sub-states based on which pillar keys you've populated
(this mirrors the upstream `salt-formula-salt` convention):

| Pillar has...                                              | Includes               |
| ------------------------------------------------------------ | ---------------------- |
| always                                                       | `salt.pkgrepo`, `salt.logrotate.cleanup` |
| `salt_formulas:list`                                         | `salt.formulas`          |
| `salt:master` (more than the default)                        | `salt.master`, `salt.logrotate.master` |
| `salt:master` + `salt:exporter:enabled`                      | `salt.exporter`          |
| `salt:cloud`                                                 | `salt.cloud`             |
| `salt:ssh_roster`                                            | `salt.ssh`               |
| `salt:minion` + `master_type` set                            | `salt.minion`            |
| `salt:minion` but no `master_type`                           | `salt.standalone`        |
| `salt:minion` + `salt:minion_watchdog:enabled`               | `salt.minion_watchdog`   |
| `salt:api`                                                   | `salt.api`               |
| `salt:syndic`                                                | `salt.syndic`            |
| `salt:extensions:enabled` (default on)                       | `salt.extensions`        |
| `salt:saltgui:enabled`                                       | `salt.saltgui`           |
| `salt:sync_custom_modules` (default on)                      | `salt.sync`              |

A host can be master + api + minion + saltgui + exporter + watchdog all at
once (a common single-box setup) simply by populating all the relevant pillar
keys. `salt.exporter` is gated on the same `salt:master` check as
`salt.master` since it reads the local master's event bus; `salt.minion_watchdog`
is gated on the same `salt:minion` check as `salt.minion`/`salt.standalone`
since it protects the local minion service - each is additionally its own
opt-in (`enabled: true`, off by default).

## Log rotation

The formula can manage `/etc/logrotate.d` entries for `salt-minion`,
`salt-master`, `salt-api`, `salt-cloud`, the minion watchdog, and every
file-logging `salt-exporter` instance.
It is opt-in to avoid changing existing deployments. Cleanup still runs with a
narrow allow-list so snippets previously created by this formula are removed
when components or exporter instances are disabled or deleted:

```yaml
salt:
  logrotate:
    enabled: true
    components:
      minion:
        paths: [/var/log/salt/minion]
        frequency: daily
        rotate: 14
        maxsize: 250M
      master:
        paths: [/var/log/salt/master]
      api:
        paths: [/var/log/salt/api]
      cloud:
        paths: [/var/log/salt/cloud]
      watchdog:
        # paths left unset - tracks salt:minion_watchdog:log_file
        rotate: 8
      exporter:
        rotate: 14
        per_instance: true
        filename_prefix: salt-exporter-

  exporter:
    enabled: true
    version: '0.13.0'
    instances:
      default:
        log_file: /var/log/salt-exporter/default.log
```

`api`, `cloud`, `master`, and `minion` paths must match the corresponding Salt
logging configuration. The `watchdog` component is different: leave its `paths`
empty and it follows `salt:minion_watchdog:log_file`, so the two cannot drift.
Its snippet is only written when `salt:minion_watchdog:enabled` is true, and is
removed again when the watchdog is disabled. Exporter file logging is enabled
per instance with `log_file`;
the systemd unit then sends stdout and stderr to that file. By default, each
instance receives its own snippet (`salt-exporter-<instance>`), allowing
independent retention and size policies. Instances without `log_file` continue
using the journal and are not added to logrotate.

Every component supports `enabled`, `filename`, `paths`, `frequency`, `rotate`,
`maxage`, `size`, `minsize`, `maxsize`, `missingok`, `notifempty`, `compress`,
`delaycompress`, `dateext`, `dateformat`, `copytruncate`, `sharedscripts`,
`create`, `su`, `olddir`, `prerotate`, `postrotate`, `firstaction`,
`lastaction`, and `extra_directives`. Boolean settings accept `true`, `false`,
or `null`: `true` emits the positive directive, `false` emits its explicit
negative counterpart, and `null` inherits global logrotate behaviour by
omitting both. Component values merge over `defaults.yaml`, so only overrides
need to be set in pillar.


## Common deployment examples

The examples below are intentionally minimal. Start with the closest pattern,
then copy additional settings from `pillar.example` as needed.

### Managed minion

```yaml
salt:
  minion:
    master: salt.example.org
    master_type: str
```

### Multi-master minion with failover

```yaml
salt:
  minion:
    master:
      - salt-master-01.example.org
      - salt-master-02.example.org
    master_type: failover
    master_shuffle: true
    master_alive_interval: 30
```

### Master with API and local minion

```yaml
salt:
  master:
    interface: 0.0.0.0
    file_roots:
      base:
        - /srv/salt
    pillar_roots:
      base:
        - /srv/pillar

  api:
    rest_cherrypy:
      host: 127.0.0.1
      port: 8000
      disable_ssl: true

  minion:
    master: 127.0.0.1
    master_type: str
```

### Masterless minion

Omit `master_type` to select `salt.standalone` automatically.

```yaml
salt:
  minion:
    file_client: local
    startup_states: highstate
    file_roots:
      base:
        - /srv/salt
    pillar_roots:
      base:
        - /srv/pillar
```

### Master with two exporter instances

```yaml
salt:
  master:
    interface: 0.0.0.0

  exporter:
    enabled: true
    version: '0.13.0'
    instances:
      internal:
        listen_address: 127.0.0.1:2112
        config:
          listen_address: 127.0.0.1:2112
          telemetry_path: /metrics
          log_level: info
      monitoring:
        listen_address: 0.0.0.0:9212
        log_file: /var/log/salt-exporter/monitoring.log
        config:
          listen_address: 0.0.0.0:9212
          telemetry_path: /metrics
          log_level: warning
```

### Per-instance exporter rotation and log ownership

```yaml
salt:
  logrotate:
    enabled: true

  exporter:
    enabled: true
    version: '0.13.0'
    log:
      directory_mode: '0750'
      file_mode: '0640'
    instances:
      local:
        log_file: /var/log/salt-exporter/local.log
        logrotate:
          rotate: 30
          maxsize: 500M
      remote:
        log_file: /srv/log/salt-exporter/remote.log
        log:
          directory_user: monitoring
          directory_group: monitoring
          file_user: monitoring
          file_group: monitoring
        logrotate:
          filename: salt-exporter-remote-events
          rotate: 7
          maxsize: 50M
```

Set `manage_directory` or `manage_file` to `false` under `exporter:log` or an
individual instance's `log` block when another formula owns those paths.

## Configuration precedence

Configuration is merged in this order, with later sources winning:

1. Formula defaults from `defaults.yaml`.
2. OS-family and OS-specific map data.
3. Pillar data under `salt:`.

Most master and minion keys are passed through to Salt configuration files, so
valid native Salt options can be supplied even when they are not explicitly
listed in `pillar.example`. Formula-specific options such as `pkgrepo`,
`extensions`, `exporter`, `minion_watchdog`, and `logrotate` are documented in
this README and in `defaults.yaml`.

## Logrotate configuration reference

Global settings live under `salt:logrotate`; component settings live under
`salt:logrotate:components:<name>`. Component values merge over the formula
defaults.

| Setting | Type / example | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Enables management globally or for one component. |
| `package` | `logrotate` | Package installed when global support is enabled. |
| `config_dir` | `/etc/logrotate.d` | Destination directory for generated snippets. |
| `validate` | `true` | Validate each candidate snippet before replacing the live file. |
| `validate_command` | `/usr/sbin/logrotate --debug` | Command used by `file.managed.check_cmd`. |
| `cleanup` | `true` | Remove inactive formula-managed snippets. |
| `managed_filenames` | list | Known non-instance filenames eligible for cleanup. |
| `exporter_filename_prefix` | `salt-exporter-` | Narrow prefix used to find stale exporter instance snippets. |
| `salt_common_filename` | `salt-common` | Packaged snippet removed once `enabled` and `cleanup` are both true, since it double-rotates `/var/log/salt/*`. Set to `''` to keep it. |
| `filename` | `salt-minion` | Name of the generated file in `config_dir`. |
| `paths` | list | Log paths or globs included in the stanza. |
| `frequency` | `daily` | One of `hourly`, `daily`, `weekly`, `monthly`, or `yearly`. |
| `rotate` | `14` | Number of rotated files retained. |
| `maxage` | `90` | Remove rotations older than this many days; `null` omits it. |
| `size` | `100M` | Rotate only after reaching this size. |
| `minsize` | `10M` | Frequency must be reached and file must be at least this size. |
| `maxsize` | `250M` | Rotate once this size is reached, even before the frequency. |
| `compress` | `true` | Compress old logs. |
| `delaycompress` | `true` | Delay compression until the next rotation. |
| `dateext` / `dateformat` | `true`, `-%Y%m%d` | Use date-based suffixes. |
| `missingok` | `true` | Do not fail when a log file is absent. |
| `notifempty` | `true` | Do not rotate empty files. |
| `copytruncate` | `true` | Copy and truncate an open file instead of reopening it. |
| `create` | `0640 root root` | Create a replacement file; blank omits the directive. |
| `su` | `root root` | User and group used while rotating. |
| `olddir` | `/var/log/archive` | Store rotated files in another directory. |
| `sharedscripts` | `true` | Run action scripts once for all matching paths. |
| action fields | multiline string | `prerotate`, `postrotate`, `firstaction`, or `lastaction`. |
| `extra_directives` | list | Additional raw logrotate directives. |
| `per_instance` | `true` | Exporter only: create one snippet per file-logging instance. |
| `filename_prefix` | `salt-exporter-` | Exporter per-instance snippet prefix. |

`size` cannot be combined with `minsize` or `maxsize`; the template rejects
that combination. `minsize` and `maxsize` retain their normal interval-aware
semantics and may be used together. Unsafe filenames, empty path lists, invalid
frequencies, and an unacknowledged `copytruncate` plus `postrotate` combination
also fail during rendering rather than producing a broken snippet.

Use `size` by itself. `minsize` and `maxsize` may be combined with an interval
when their different semantics are intentional. `copytruncate` is the safest generic default for
Salt processes that keep files open, though it has a small race window. Where a
component reliably reopens logs on signal, disable `copytruncate` and provide a
`postrotate` action instead.

### Size-based minion rotation

```yaml
salt:
  logrotate:
    enabled: true
    components:
      minion:
        frequency: daily
        rotate: 30
        maxsize: 250M
        maxage: 90
        dateext: true
        dateformat: '-%Y%m%d'
```

### Reopen logs instead of using copytruncate

```yaml
salt:
  logrotate:
    enabled: true
    components:
      minion:
        copytruncate: false
        create: '0640 root root'
        sharedscripts: true
        postrotate: |
          systemctl kill -s HUP salt-minion.service >/dev/null 2>&1 || true
```

Test generated snippets before relying on the scheduled run:

```console
logrotate --debug /etc/logrotate.conf
logrotate --debug /etc/logrotate.d/salt-minion
```

## Sub-states Reference

### salt.pkgrepo - Package Repository Management

Maintains the official Salt apt repository definition. Never hand-builds repo
lines; instead fetches the canonical `salt.sources` file from
`saltstack/salt-install-guide` releases, so it always matches what Salt Project
actually publishes. Handles GPG key lifecycle properly: re-runs `gpg --dearmor`
on `onchanges` so a rotated upstream key gets picked up automatically.

**What it does:**
- Cleans up legacy repo/key paths from earlier formula iterations
  (`/etc/apt/sources.list.d/salt.list`, `/usr/share/keyrings/salt-archive.pgp`, etc.)
- Creates `/etc/apt/keyrings/` directory (mode 0755)
- Installs `gnupg` package
- Downloads the public key from `keyring_url` (default:
  `https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public`)
- Dearmors the key to `/etc/apt/keyrings/salt-archive-keyring.pgp`
  (runs on every `onchanges` of the armored source)
- Downloads the `.sources` file from
  `https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.sources`
  to `/etc/apt/sources.list.d/salt.sources`
- When `pin_version: true`, writes an apt pin at
  `/etc/apt/preferences.d/salt-pin-1001` restricting `salt-*` packages to
  `version_series` (e.g. `3008.*`)

**Pillar keys:** See `salt:pkgrepo.*` in defaults.yaml. Key options include
`sources_guide_ref`, `keyring_hash` (optional SHA-256 for strict pinning), and
`legacy_paths` (list of legacy repo/key locations to clean up).

### salt.master - Master Configuration

Installs the `salt-master` package, writes configuration into
`<config_path>/master.d/defaults.conf`, and manages the service. Uses the Jinja
template at `files/master.d/defaults.conf` which covers **~1800 lines** of Salt
master configuration options, each with full documentation comments.

**What it does:**
- Installs `salt-master` (or skips if `install_packages: false`)
- Recursively deploys `<config_path>/master.d/` from templates (TOFS or bundled)
- Cleans the config.d directory (`clean_config_d_dir`, default true)
- Excludes files starting with `_` from deployment
- Enables and starts the `salt-master` service
- Removes legacy `/etc/salt/master` file if `master_remove_config: true`
- Removes old `_defaults.conf` file from earlier formula versions

**Configuration keys written to `master.d/defaults.conf`:** Any key under
`salt:master` is written verbatim. Keys not in pillar fall back to the full
Salt master config reference (all defaults are commented out with descriptions).
The template also supports lookup under `salt:` top-level for a few shared keys
(`interface`, `worker_threads`, etc.).

**Major configuration categories covered by the template:**
- **Primary settings**: `interface`, `publish_port` (4505), `ret_port` (4506),
  `pidfile`, `pki_dir` (`/etc/salt/pki/master`), `cachedir`, `sock_dir`,
  `keep_jobs`, `output`, `timeout`, `loop_interval`
- **Large-scale tuning**: `max_open_files` (100K), `worker_threads` (5),
  ZMQ high-water-marks (`salt_event_pub_hwm: 20000`, `event_publisher_pub_hwm: 10000`),
  batch_safe_limit/size
- **Security**: `open_mode`, `auto_accept`, `autosign_file`,
  `permissive_pki_access`, `publisher_acl`, `publisher_acl_blacklist`,
  `sudo_acl`, `token_expire` (12h), `file_recv`, `sign_pub_message`, `ssl:`
- **LDAP authentication**: Full `auth.ldap.*` namespace for directory service auth
- **Salt-SSH**: `roster_file`, `ssh_log_file`, `ssh_minion_opts`, `ssh_use_home_key`
- **State system**: `state_top`, `master_tops`, `external_nodes`, `renderer`,
  `jinja_trim_blocks`, `failhard`, `state_verbose`, `state_output`, `state_aggregate`
- **File Server**: `file_roots`, `top_file_merging_strategy`, `env_order`,
  `hash_type`, `file_buffer_size`, `file_ignore_regex/glob`, `fileserver_backend`,
  `gitfs_*` (provider, remotes, user, password, pub/privkey, env whitelist/blacklist),
  `s3.keyid/key/buckets`, `pillar_roots`, `ext_pillar`, `pillar_cache`,
  `pillar_gitfs_*`, `fileserver_followsymlinks/ignoresymlinks/limit_traversal`
- **Syndic**: `order_masters`, `syndic_master`, `syndic_master_port`,
  `syndic_pidfile`, `syndic_log_file`, `syndic_user`, `syndic_failover`, `syndic_wait`
- **Peer Publish**: `peer`, `peer_run` - allow minions to execute commands on other minions
- **REST APIs**: `rest_cherrypy:` and `rest_tornado:` sections
- **Other**: `event_return/blacklist/whitelist`, `max_event_size`, `ping_on_rotate`,
  `preserve_minion_cache`, `con_cache`, `enable_gpu_grains`, `job_cache`,
  `minion_data_cache`, `cache` (localfs), `memcache_*` options

### salt.minion - Minion Configuration

Installs the `salt-minion` package, writes configuration into
`<config_path>/minion.d/defaults.conf`, manages the service and PKI. Uses the
Jinja template at `files/minion.d/defaults.conf` which covers **~1270 lines**.

**What it does:**
- Installs `salt-minion`
- Recursively deploys `<config_path>/minion.d/` from templates
- Enables and starts the `salt-minion` service
- Removes legacy `/etc/salt/minion` file if `minion_remove_config: true`
- Creates PKI directory (`pki_dir`, default `/etc/salt/pki/minion`, mode 0700)
- Manages `minion.pem` (mode 0400) and `minion.pub` (mode 0644)

**Configuration keys written to `minion.d/defaults.conf`:** Any key under
`salt:minion` is written verbatim. The template handles complex structures
including arrays, nested dicts, schedule blocks, and ext_pillar definitions.

**Major configuration categories covered:**
- **Primary settings**: `master` (multi-master support), `master_type` (str/failover/disable),
  `random_master`, `master_shuffle`, `master_alive_interval`, `master_fallback`,
  `master_fallback_interval`, `ipv6`, `retry_dns`, `master_port` (4506),
  `user`, `sudo_user`, `pidfile`, `root_dir`, `conf_file`, `pki_dir`, `id`,
  `minion_id_caching`, `append_domain`
- **Grains**: Custom static grains (`grains: {}`), `grains_refresh_every` (1min),
  `grains_cache`, `grains_deep_merge`, `grains_cache_expiration` (300s)
- **Connection/reconnection**: `acceptance_wait_time`, `acceptance_wait_time_max`,
  `rejected_retry`, `random_reauth_delay`, `auth_timeout`, `auth_tries`, `master_tries`,
  `auth_safemode`, `ping_interval`, `con_cache`
- **Reconnect backoff**: `recon_default` (100ms), `recon_max` (5s), `recon_randomize` -
  exponential backoff with randomization to prevent thundering herd on large estates
- **Caching**: `cachedir`, `sock_dir`, `cache_jobs`, `backup_mode` (minion)
- **Modules/returners**: `disable_modules`, `disable_returners`, `whitelist_modules`,
  `module_dirs`, `returner_dirs`, `states_dirs`, `render_dirs`, `utils_dirs`,
  `providers`, `modules_max_memory`, `cython_enable`
- **State management**: `renderer` (yaml_jinja), `failhard`, `autoload_dynamic_modules`,
  `clean_dynamic_modules`, `environment/saltenv`, `pillarenv`, `state_top`,
  `startup_states` (highstate/sls/top), `sls_list`, `top_file`, `state_aggregate`
- **File server** (minion side): `file_client` (remote/local), `file_roots`,
  `fileserver_backend`, `fileserver_followsymlinks/ignoresymlinks/limit_traversal`,
  `hash_type`, `gitfs_*` options, `pillar_roots`, `ext_pillar`,
  `pillar_gitfs_*`, `file_recv_max_size`
- **Logging**: `log_file` (`/var/log/salt/minion`), `log_level` (warning),
  `log_level_logfile`, `log_datefmt`, `log_fmt_console`, `log_fmt_logfile`,
  `log_granular_levels`, `zmq_monitor`
- **Scheduled jobs**: Full `schedule:` block support - each named entry defines
  function, interval (minutes/hours/days/etc.), kwargs, splay, run_on_start, etc.
- **Pillar**: `pillar_opts`, `pillar_safe_render_error`, `pillar_source_merging_strategy`,
  `pillar_merge_lists`, `pillar_raise_on_missing`
- **Security**: `open_mode`, `permissive_pki_access`, `verify_master_pubkey_sign`,
  `master_finger`, `ssl:` settings, `state_verbose`, `state_output`, `state_output_diff`,
  `state_output_profile`
- **Thread/process**: `multiprocessing` (true), `ipc_mode` (ipc/tcp)
- **Keepalive**: `tcp_keepalive` (True), `tcp_keepalive_idle` (300s),
  `tcp_keepalive_cnt`, `tcp_keepalive_intvl`
- **Returners**: Multiple returner support (`return: mysql,slack,redis`)
- **Elasticsearch/MongoDB** connections when configured
- **Miscellaneous**: `test:*` module config, `update_url/restart_services`,
  `event_match_type`, `runner_returns`, `thin_extra_mods`

### salt.standalone - Masterless Minion

Same package/config as `salt.minion`, but the service is intentionally managed
differently: when no `master_type` is set, the minion runs masterlessly with
`file_client: local`. The service stays **enabled and running** (vs. stopped for a
connected minion).

### salt.api - Salt-API (REST API)

Installs `salt-api` and manages the `salt-api` service. Simply includes
`salt.master` first (ensures the master package is installed), then installs the
api package and starts its service with a dependency on the master service.

**Pillar keys:** Any key under `salt:api` is written to master.d for `rest_cherrypy:`
and `external_auth:` configuration. The most common setup uses `rest_cherrypy` with:
- `port`, `host`, `disable_ssl`, `collect_stats`
- `external_auth.pam:` for PAM-based eauth with role-based command grants

### salt.syndic - Syndic (Multi-Master Hierarchy)

Installs `salt-syndic` and manages the `salt-syndic` service. Includes
`salt.master` first, then installs and starts the syndic daemon which forwards
commands to a higher-level master (`syndic_master`). Supports multi-syndic with
random or ordered failover.

### salt.cloud - Cloud Provisioning

Installs `salt-cloud` (optionally with `apache-libcloud` via pip), deploys cloud
provider maps/profiles from templates, and manages cloud credential certificates.

**What it does:**
- Optional: installs python3-pip + apache-libcloud into the bundled onedir Python
  when `use_pip: true`
- Installs `salt-cloud` package
- Deploys cloud.providers.d/, cloud.profiles.d/, cloud.maps.d/ from bundled templates
- Renders cloud config sections from pillar data (providers, profiles, maps)
- Sets restrictive permissions on providers directory (dir 700, files 600)
- Supports custom cloud certificates via `salt_cloud_certs` pillar

**Pillar keys:** `cloud.providers`, `cloud.profiles`, `cloud.maps` (see Salt's
cloud documentation for format). Provider templates included: EC2, Saltify, GCE,
RSOS.

### salt.ssh - Salt-SSH Roster

Installs `salt-ssh` and generates the roster file from pillar at `/etc/salt/roster`.

**Pillar keys:** `salt:ssh_roster:` - dict keyed by minion name with `host`,
`user`, optional `priv`, `timeout`, `port`, `minion_opts` per entry.

### salt.extensions - Bundled Python Extensions (ONEDIR)

Since Salt 3006+, the onedir packages ship a bundled Python at
`/opt/saltstack/salt/bin/python3`. This state installs third-party packages into
that environment instead of the system Python:

- **saltext-* packages**: Full saltext extensions (`saltext-kubernetes`, etc.)
  - Automatically adds `saltext-` prefix if missing
  - Uses `pip.installed` with `bin_env:` pointing to the bundled interpreter
- **Arbitrary pip packages**: Any python package (`PyMySQL`, `python-telegram-bot`, etc.)
  Same bin_env target as saltext entries.
- **gitfs_provider**: Installs the provider library into the onedir env:
  - `pygit2`: Also installs `libgit2-dev` from apt; uses `--no-deps` to avoid
    rebuilding cffi against a different ABI than what Salt bundles
  - `gitpython`: Installs GitPython package
  - `dulwich`: Installs dulwich package

**build_dependencies:** apt packages needed before pip installs (e.g. `libgit2-dev`).

#### Beacon dependencies

Salt's beacons import third-party libraries that the onedir package does not
vendor. Configure `beacons:` in minion config without them and the beacon never
fires — no error, no log line. `salt:extensions:beacon_deps` installs them.

`enabled` is a tri-state, and the default is `auto`:

| Value | Behaviour |
| --- | --- |
| `auto` (default) | Install only what *this* minion's configured beacons need |
| `true` | Install the whole `apt` + `pip` bundle regardless of beacon config |
| `false` | Install nothing |

**`auto` is safe to leave on formula-wide.** It reads the same pillar that
`files/minion.d/beacons.conf` renders from — `salt:beacons`, then
`salt:minion:beacons` merged over it — so a minion with no beacon pillar gets
nothing at all, including no compiler toolchain. Deps also cannot drift from
config: adding a beacon to pillar is what pulls its library in.

The mapping lives in `salt:extensions:beacon_deps:beacon_map`:

| Beacon | pip | apt |
| --- | --- | --- |
| `inotify` | `pyinotify`, `pyasyncore` | — |
| `network_settings`, `network_info` | `pyroute2` | — |
| `journald` | `systemd-python` | `build-essential`, `libsystemd-dev`, `pkg-config` |
| `watchdog` | `watchdog` | — |
| `telegram_bot_msg` | `python-telegram-bot` | — |
| `twilio_txt_msg` | `twilio` | — |
| `napalm` | `napalm` | — |

Beacons not listed need nothing beyond what the onedir Python already bundles —
`psutil` covers `status`, `load`, `memusage`, `swapusage`, `diskusage`, `service`
and `sh`. An unrecognised beacon name contributes nothing rather than erroring,
so custom beacons are safe. The map is merged, so adding one key from pillar does
not drop the rest:

```yaml
salt:
  extensions:
    beacon_deps:
      beacon_map:
        my_custom_beacon:
          pip:
            - some-library
```

Beacons declared under an arbitrary key with an explicit `beacon_module` (the
way you run two instances of one beacon) resolve correctly in both the dict and
the list config forms — the module name is what's looked up, not the key.

Three things worth stating explicitly, because all three are easy to get wrong:

- **Do not apt-install `python3-pyinotify` / `python3-pyroute2`.** They install
  into the *system* Python, which the onedir minion never imports — the beacon
  stays broken while the packages look present. Only `libsystemd-dev` belongs on
  the apt side, and only because `systemd-python` is a C extension built at pip
  time. `build-essential` and `pkg-config` come along for that build.
- **`pyasyncore` is not a beacon dependency in its own right.** `pyinotify`
  imports the stdlib `asyncore` module, removed in Python 3.12 by
  [PEP 594](https://peps.python.org/pep-0594/); `pyasyncore` is the extracted
  standalone copy that keeps that import working. Harmless on interpreters that
  still ship `asyncore`, so it is installed unconditionally alongside pyinotify.
- **`journald` is the only mapped beacon that needs a compiler.** Under `auto`,
  hosts that don't read the journal never see `build-essential`. Setting
  `enabled: true` puts it everywhere — reserve that for hosts whose beacons are
  configured outside this formula.

Anything already listed in `salt:extensions:pip` is skipped here rather than
installed twice, and the apt side merges into the same `pkg.installed` state as
`build_dependencies`.

`tests/validate_extensions_beacon_deps.py` renders `extensions.sls` against a
synthetic pillar and asserts on the resulting package lists.

### salt.saltgui - SaltGUI Web Interface

Deploys SaltGUI from a pinned release tarball (default) or git checkout. SaltGUI is
a static web app that talks to salt-api's `rest_cherrypy` endpoint.

**Method options:**
- `archive` (default): Downloads a versioned tarball from GitHub releases. Recommended.
  Tags have no `v` prefix (e.g., `1.33.0`).
- `git`: Clones the repo via `git.latest`, tracks a configurable ref/branch.

**Optional nginx vhost:** When `saltgui.nginx.enabled: true`, deploys an nginx config
that reverse-proxies `/api` to salt-api and serves static content from target directory.

### salt.minion_watchdog - Crash/Hang Recovery (Minion-Only)

A cron-driven script (`salt-minion-watchdog.sh.jinja`) that detects and recovers
from three classes of minion failure:

1. **Crash/OOM**: Process-existence check + best-effort dmesg/journalctl OOM detection
2. **Hang/Wedged**: Log-file staleness - process alive but log not written in `stale_minutes`
3. **Known fatal patterns**: Scans new log content for dispatch timeouts, ZMQ errors,
   auth failures, connection errors

**Recovery:** SIGKILL any salt-minion processes + restart via systemctl (fallback to service).

**Circuit breaker:** Prevents restart loops - after `max_restarts` restarts within
`window_seconds`, stops auto-restarting and triggers an alert (`alert_cmd`).

**Pillar keys:** See `salt:minion_watchdog.*` in defaults.yaml: `cron.*`,
`circuit_breaker.max_restarts` (3), `circuit_breaker.window_seconds` (3600),
`stale_minutes` (20), `extra_error_patterns[]`, `alert_cmd`.

### salt.exporter - Prometheus Exporter for Salt Metrics (Master-Only)

Deploys [salt-exporter](https://kpetremann.github.io/salt-exporter/) - a Prometheus
exporter for salt-master job/event metrics. Install is versioned, checksum-verified, and
architecturally-aware (amd64/arm64/386).

**What it does:**
- Resolves `grains['cpuarch']` + `grains['kernel']` to the correct GoReleaser asset
- Verifies download against release `checksums.txt`
- Installs to `<install_dir>/salt-exporter-<version>` and creates a symlink
  at `<install_dir>/salt-exporter` for atomic upgrades/rollbacks
- Creates a dedicated system user/group (`salt-exporter`)
- Deploys a hardened systemd unit targeting ~9-10/10 under `systemd-analyze security`:
  - Non-root user, no shell, `NoNewPrivileges=true`, empty CapabilityBoundingSet
    (unless privileged port), `ProtectSystem=strict`
  - Full namespace lockdown: ProtectKernelTunables/Modules/Logs/CGroups/Clock/Hostname,
    RestrictNamespaces/Realtime/SUIDSGID, LockPersonality, MemoryDenyWriteExecute, etc.
  - Syscall filtering (allow @system-service, deny @privileged/@resources/@mount/etc.)
  - DevicePolicy=closed, strict UMask, resource limits
- Writes per-instance config and environment files
- Optional firewall rules (ufw or firewalld) per instance
- Optional Prometheus scrape-label metadata

**Multi-instance support:** Add more keys under `salt:exporter:instances` for multiple
exporters on different ports/event sources sharing the same binary.

**Internal mirror:** Set `release_base_url` to an artifact repository following GitHub's
layout, or use `download_url_override`/`checksums_url_override` for exact URLs.

**Pillar keys:** See `salt:exporter.*` in defaults.yaml: `instances.default`,
`firewall.backend (ufw|firewalld)`, `prometheus.enabled + labels[]`,
`service.hardening_overrides.*`.

### salt.sync - Custom Module Sync

Runs `saltutil.sync_all` on every highstate so changes to custom
`_modules/`, `_states/`, `_beacons/`, `_utils/` take effect immediately.

## The GPG / apt repo fix

The previous version of this setup hand-built a
`deb [signed-by=...] <url> stable main` line and fetched the GPG key with:

```
unless: test -s /usr/share/keyrings/salt-archive.pgp
```

Both of those are recurring sources of pain:

1. Hand-built repo lines drift out of sync whenever Salt Project changes
   the repo layout (component names, arch handling, etc. have all changed
   at least once since the Broadcom migration).
2. `unless: test-s <file>` means the key is fetched **exactly once**. If
   Salt Project ever rotates the signing key, the host keeps trusting the
   old one forever - `apt update` starts failing with a GPG error that
   gives no hint that "the key is stale" is the actual problem.

`pkgrepo.sls` instead:

- downloads the canonical `salt.sources` file published by
  `saltstack/salt-install-guide` (the exact same file the official install
  docs tell you to fetch), so the repo definition can never drift from
  what's actually published;
- re-runs `gpg --dearmor` on `onchanges` of the downloaded key, so a
  rotated key gets picked up the next time the state runs instead of
  silently going stale;
- cleans up every legacy repo/key path this formula (and common
  community tutorials) has historically written to, so nothing shadows
  the current config;
- writes the apt pin file at `/etc/apt/preferences.d/salt-pin-1001`
  (matching Salt Project's own documented pin filename) when
  `salt:pin_version` is true, restricting upgrades to `salt:version_series`.

Two more concrete bugs turned up while auditing the old `files/` tree for
this refactor, both now fixed by deletion:

- `files/salt-archive-keyring.pgp` was a **static GPG key committed to the
  repo in Feb 2023** and never referenced by any state that still exists.
  A binary key file frozen at a point in time is exactly the kind of
  landmine that causes "it worked for two years, then apt started failing
  with a signature error" - if anything had still pointed at it, it would
  have silently stopped matching the moment Salt Project rotated keys.
  Removed; `pkgrepo.sls` fetches the key fresh.
- `files/master.d/f_defaults.conf` and `files/minion.d/f_defaults.conf`
  (plus their `files/default/` copies) were **stale, near-complete
  duplicates** of `defaults.conf`, sitting in the same directory without
  being excluded by `exclude_pat`. Since Salt's `default_include:
  master.d/*.conf` merges every matching file in filename order, and
  `f_defaults.conf` sorts *after* `defaults.conf`, the older duplicate's
  values were silently winning over the current `defaults.conf` for every
  overlapping key. Removed - `defaults.conf` is the single source of
  truth now.

## Extensions ("the extra bits Salt 3008 requires")

Since Salt 3006, the onedir packages ship and run their own bundled
Python under `/opt/saltstack/salt`, completely separate from the system
Python. This means:

- `apt install python3-pygit2` installs into the **system** Python - the
  onedir salt-master never sees it.
- A plain `pip install saltext-kubernetes` (system pip) has the same
  problem.

The fix is to install into the bundled interpreter instead, via
`bin_env: /opt/saltstack/salt/bin/python3` (this is also what the
`salt-pip` CLI wrapper does under the hood). `extensions.sls` does this
for three pillar-driven lists, so you never need to hand-write a new
state to add a dependency:

```yaml
salt:
  extensions:
    enabled: true
    gitfs_provider: pygit2       # pygit2 | gitpython | dulwich | ''
    saltext:                     # saltext-* packages ('saltext-' prefix optional)
      - kubernetes
      - mysql
      - proxmox
    pip:                         # any other python package
      - PyMySQL
      - python-telegram-bot
    build_dependencies:          # apt packages needed to build the above
      - default-libmysqlclient-dev
```

`gitfs_provider: pygit2` installs `libgit2-dev` from apt (for the C
library/headers) and `pygit2` into the onedir python with `--no-deps`
(avoids pip rebuilding `cffi` against a different ABI than the one
already bundled with Salt - a common source of import errors after
installing pygit2 the naive way).

## SaltGUI

The previous setup did:

```yaml
saltgui:
  git.latest:
    - name: https://github.com/erwindon/SaltGUI.git
    - target: /srv/saltgui
    - branch: master
```

which tracks `master` forever - every highstate can pull in unreviewed
upstream changes, and there's no way to know which commit is actually
deployed on a given host. `saltgui.sls` defaults to downloading a pinned
release tarball instead:

```yaml
salt:
  saltgui:
    enabled: true
    method: archive        # or 'git' if you deliberately want to track a ref
    version: '1.33.0'      # SaltGUI tags have no 'v' prefix - check upstream tags first
    target: /srv/saltgui
    nginx:                 # optional - set enabled: true for a ready-made vhost
      enabled: true
      server_name: salt.example.org
      api_backend: http://127.0.0.1:8000
```

SaltGUI is a static app that talks to salt-api's `rest_cherrypy`
endpoint - make sure `salt:api` is configured (see `pillar.example`)
and reachable from wherever SaltGUI is served.

## Salt Exporter (Prometheus metrics, master-only)

Folded in from the former standalone `salt-exporter` formula.
[salt-exporter](https://kpetremann.github.io/salt-exporter/) is a
Prometheus exporter for salt-master job/event metrics, installed from a
versioned GitHub (or internal mirror) release - never from source.

```yaml
salt:
  exporter:
    enabled: true
    version: "0.13.0"      # required once enabled - release tag, no leading 'v'
    instances:
      default:
        listen_address: "0.0.0.0:2112"
        config:
          listen_address: "0.0.0.0:2112"
          telemetry_path: "/metrics"
```

Highlights:

- **Master-only.** `salt.exporter` is included only when `salt:master` is
  populated *and* `salt:exporter:enabled` is true - see the include table
  above. It reads the local salt-master's event bus, so it has nothing to
  do on a plain minion.
- **Architecture-aware, checksum-verified.** Resolves
  `grains['cpuarch']`/`grains['kernel']` to the right GoReleaser asset and
  verifies against the release's `checksums.txt` - no hardcoded SHA256s
  anywhere in this formula or your pillar.
- **Versioned, atomic upgrades.** Installs to
  `<install_dir>/salt-exporter-<version>` and flips
  `<install_dir>/salt-exporter` to it via `file.symlink`. Rolling back is:
  set `salt:exporter:version` back and re-apply.
- **Dedicated user, hardened systemd unit.** Runs as a non-root, no-shell
  system account under a unit that aims for ~9-10/10 under
  `systemd-analyze security` (empty capability set unless the instance's
  port is privileged, `ProtectSystem=strict`, syscall filtering, etc - see
  `exporter/files/salt-exporter.service.jinja`). Every directive is overridable
  via `salt:exporter:service:hardening_overrides`.
- **Multiple instances.** Add more keys under `salt:exporter:instances` to
  run several exporters (different ports/event sources) off one shared,
  checksum-verified binary.
- **Internal mirror support.** `salt:exporter:release_base_url` repoints
  downloads at an artifact repository following the same layout GitHub
  uses; `download_url_override`/`checksums_url_override` bypass the
  template entirely for an exact URL.
- **Optional extras, off by default.** `salt:exporter:firewall` (ufw or
  firewalld allow rule per instance) and `salt:exporter:prometheus`
  (publishes scrape-label metadata under pillar for a Prometheus
  formula/mine consumer elsewhere - this formula doesn't assume how you
  run Prometheus).

See `pillar.example` for a full worked example. One bug fixed while
folding this in: the original standalone formula's `install.sls` and
`config.sls` both did `include: [salt-exporter.user]`, but no `user.sls`
ever shipped - the user/group creation state didn't actually exist.
`exporter/user.sls` now provides it for real.

## Minion configuration

Everything under the `salt:minion` pillar key is written into
`<config_path>/minion.d/defaults.conf` by `minion.sls`, via the Jinja
template at `files/minion.d/defaults.conf`. There's no separate "minion
config" pillar structure to learn - the template's `get_config()` macro looks
up each Salt minion setting by name under `salt:minion` first, falls back to
`salt:<name>` (shared with the master config) for a few keys, and otherwise
leaves Salt's own documented default commented out. This means any key the Salt
minion itself understands can go in pillar as-is:

```yaml
# pillar/salt/minion.sls
salt:
  minion:
    master: salt.example.org
    master_type: str
    log_level: warning
    grains:
      role: webserver
      datacenter: dc1
```

Whether this lands you in `salt.minion` or `salt.standalone` depends on
`master_type` - see the include table above (`salt:minion` +
`master_type` set → `salt.minion`; `salt:minion` with no `master_type` →
masterless/`salt.standalone`).

### Scheduled jobs (`schedule`)

The minion's built-in scheduler is configured the same way, under
`salt:minion:schedule`:

```yaml
salt:
  minion:
    schedule:
      highstate:
        - function: state.apply
        - minutes: 60
      cleanup:
        - function: cmd.run
        - hours: 24
        - kwargs:
            cmd: /usr/local/sbin/salt-minion-cleanup.sh
```

A few things worth knowing before you lean on this:

- **This renders as literal YAML text, not structured pillar data.**
  The template's schedule loop (look for `{% if 'schedule' in cfg_minion %}`
  in `files/minion.d/defaults.conf`) walks the dict and prints each
  `key: value` pair as-is, with no quoting or YAML-escaping. Simple scalar
  values (`minutes: 60`, `function: state.apply`) render fine. Anything with
  nested structure - `kwargs`, `args`, `splay` as a range, `returner_kwargs`
  - is not exercised by this formula's own examples and may not come out as
  valid YAML. **Always verify the rendered file** rather than assuming a complex
  entry worked:

  ```bash
  salt-call --local pillar.get salt:minion:schedule
  salt-call --local state.show_sls salt test=True   # or just read
  cat /etc/salt/minion.d/defaults.conf               # the file directly
  ```

- **There's no example of `schedule` in `pillar.example`.** That file's
  comment on line 42 just lists `schedule` alongside `publisher_acl`/`external_auth`/`reactor`/`engines`
  as "things that can go here" - it isn't spelled out with a worked example the way
  `exporter`/`saltgui`/`extensions` are. Treat Salt's own [schedule
  documentation](https://docs.saltproject.io/en/latest/topics/jobs/schedule.html)
  as the source of truth for what a given entry needs to look like, and the
  `salt-call` commands above as your way to confirm the pillar produced what
  you expected on the wire.

- **At least one entry is required if you reference the scheduler at all** -
  the comment directly above the block in `files/minion.d/defaults.conf` notes this;
  an empty `schedule: {}` in pillar won't render a useful block.

### Minion Configuration Categories (Full Reference)

The minion config template (`files/minion.d/defaults.conf`, ~1270 lines) covers all of
Salt's built-in minion settings organized into these sections:

| Section | Key Settings |
|---------|-------------|
| **Primary** | `master`, `master_type` (str/failover/disable), `random_master`, `master_shuffle`, `master_alive_interval`, `master_fallback`, `ipv6`, `retry_dns`, `master_port` (4506), `user`, `sudo_user`, `pidfile`, `root_dir`, `conf_file`, `pki_dir`, `id`, `minion_id_caching`, `append_domain` |
| **Authentication** | `acceptance_wait_time/max`, `rejected_retry`, `random_reauth_delay`, `auth_timeout`, `auth_tries` (7), `master_tries`, `auth_safemode`, `ping_interval`, `verify_master_pubkey_sign`, `master_finger` |
| **Reconnect backoff** | `recon_default` (100ms), `recon_max` (5s), `recon_randomize` - exponential backoff with randomization |
| **Grains** | Custom static grains, `grains_refresh_every` (1min), `grains_cache`, `grains_deep_merge`, `grains_cache_expiration` (300s) |
| **Caching** | `cachedir`, `sock_dir`, `cache_jobs`, `backup_mode` |
| **Output** | `output` (nested), `color` (True), `strip_colors` (False) |
| **Modules** | `disable_modules`, `whitelist_modules`, `module_dirs`, `returner_dirs`, `states_dirs`, `render_dirs`, `utils_dirs`, `providers`, `modules_max_memory`, `cython_enable` |
| **State system** | `renderer` (yaml_jinja), `failhard`, `autoload_dynamic_modules`, `clean_dynamic_modules`, `environment/saltenv`, `pillarenv`, `state_top`, `startup_states`, `sls_list`, `top_file`, `state_aggregate`, `state_verbose`, `state_output`, `state_output_diff`, `state_output_profile` |
| **File server** | `file_client`, `file_roots`, `fileserver_backend`, `hash_type` (md5), `gitfs_*`, `pillar_roots`, `ext_pillar`, `pillar_gitfs_*`, `file_recv_max_size` |
| **Logging** | `log_file` (/var/log/salt/minion), `log_level` (warning), `log_datefmt`, `log_fmt_console/file`, `log_granular_levels`, `zmq_monitor` |
| **Pillar** | `pillar_opts`, `pillar_safe_render_error`, `pillar_source_merging_strategy`, `pillar_merge_lists`, `pillar_raise_on_missing` |
| **Keepalive** | `tcp_keepalive` (True), `tcp_keepalive_idle` (300s), `tcp_keepalive_cnt`, `tcp_keepalive_intvl` |
| **Returners** | Multiple returner support (`return: mysql,slack,redis`) |
| **Proxy** | `proxy_host`, `proxy_port`, `proxy_username`, `proxy_password` (if applicable) |

## Credential store (`pass`, master-only)

Folded in from the former standalone `salt_pass` formula. An encrypted,
local credential store built on [`pass`](https://www.passwordstore.org/)
and GnuPG, decrypted by the master while it compiles Pillar.

Encrypted credentials live outside Pillar. Pillar carries only named
references, which the `pass_resolver` external Pillar replaces for an
authorized minion:

```yaml
backup_client:
  username: backup-client
  password: 'pass:applications/pbs-client/password'
```

```yaml
salt:
  master:
    ext_pillar:
      - stack: /srv/salt/pillarstack/stack.cfg
      - pass_resolver: {}     # must come after PillarStack
  pass:
    enabled: true
    gpg_identity: Salt Master Secrets <salt-master@example.net>
```

That is the whole configuration. `salt.pass` writes the resolver's own
options to `master.d/_pass.conf`; `store_dir`, `gpg_home`, `strict_fetch`
and `timeout` are overridable under `salt:pass` if the defaults don't suit.

### Why the resolver's config is not in Pillar

`pass_dir` and friends look like ordinary master configuration, and it is
tempting to set them under `salt:master` so `master.sls` renders them into
`master.d/defaults.conf`. Don't.

The resolver runs *during* Pillar compilation. Configuration derived from
Pillar is therefore circular, and the circle is not recoverable: if
anything stops Pillar compiling, the master cannot render the config file
that would fix it. You get a master that must be repaired by hand, and the
only symptom is `Failed to load ext_pillar pass_resolver` plus every minion
timing out.

`_pass.conf` breaks the cycle by being static. `ext_pillar` itself stays in
`salt:master` — it is read at startup, not during compilation, so it has no
bootstrap problem.

### The `_` prefix is load-bearing

`master.sls` deploys `master.d` with `file.recurse` and
`clean: {{ salt_settings.clean_config_d_dir }}` (default true), which
deletes every file in that directory it does not manage. Only `_*` names
are excluded, via `exclude_pat`.

A resolver config written there under any other name is silently removed on
the next highstate — the state output reports success, and Pillar stops
compiling for every minion. `map.jinja` refuses to render if
`salt:pass:master_config` points into `master.d` without the prefix, rather
than deploying a file that is guaranteed to disappear.

If you ever see `Failed to load ext_pillar pass_resolver`, check that the
file still exists before anything else.

### Never set `pass_variable_prefix` in Pillar

The resolver walks *every string* in the compiled Pillar dictionary. The
literal value `pass:` assigned to `pass_variable_prefix` is therefore read
as a credential reference with an empty name, and Pillar compilation fails
for that minion with `Invalid pass credential name in Pillar`. It defaults
to `pass:` in the resolver and does not need to be declared anywhere.

The same applies to any unrelated value that happens to begin with the
prefix. The bundled `pass_resolver` skips the top-level `salt` key for
exactly this reason, but data under other keys is fair game.

### Ordering and cost

- `pass_resolver` must come **after** PillarStack in `ext_pillar`;
  external Pillars run in the order configured, and the resolver operates
  on the dictionary accumulated before it.
- Each distinct reference forks `pass`, which forks `gpg`. The resolver
  memoizes per compilation, but a Pillar with many distinct credentials
  still costs one decryption each, on a master worker thread. Keep
  `pass_timeout` low (5s); the default of 30 lets one wedged `gpg-agent`
  starve the worker pool, which surfaces on minions as request timeouts.
- `sync_pillar_resolver` and `sync_renderer` are bootstrap steps and
  default to false. Each shells out to `salt-run`, occupying a worker and
  nesting a job inside the running job. Run `salt-run saltutil.sync_pillar`
  by hand after changing the module.

### The GPG identity is not rotatable in place

`pass init` records the identity in `<store_dir>/.gpg-id`. Generating a
different key later produces a keyring that cannot decrypt any existing
entry. `salt.pass` guards key creation on both the identity being absent
*and* `.gpg-id` not existing, so it will not silently mint a second key -
but confirm the identity matches before enabling:

```bash
cat /var/lib/salt/password-store/.gpg-id
gpg --homedir /etc/salt/gpgkeys --list-secret-keys
```

Back up the private key and the store immediately after setup; neither is
useful without the other.

### Managing credentials

`salt-secret` is installed at `salt:pass:helper_path` and reads values with
terminal echo disabled, so they never reach shell history:

```bash
sudo salt-secret add applications/webmail/database_password
sudo salt-secret generate infrastructure/cloudflare/api_token 40
sudo salt-secret edit applications/example/private_key   # multiline
sudo salt-secret list applications/webmail
```

The `secret_store` runner (`salt-run saltutil.sync_runners`) covers the
same ground for automation and deliberately provides no function that
returns a decrypted value, since runner arguments are recorded in job data.

### Security model

The GPG private key has no passphrase, because the master must start
unattended after a reboot. Encryption protects source control, backups, and
the credential files if copied independently. It does **not** protect
secrets from root or from an attacker controlling the running master.

Assign credential-bearing Pillar only to minions that require it - a minion
can read its own compiled Pillar. Use `show_changes: false` on
secret-bearing file states, avoid logging rendered Pillar, and treat
deletion from the store as separate from revoking the credential at its
issuer.

## Minion Watchdog (crash/hang recovery, minion-only)

Folded in from the former standalone `salt-minion-watchdog` formula. A
cron-driven script that detects and recovers from an unhealthy local
`salt-minion`:

1. **Crash / OOM-kill** - process-existence check (`pgrep`/`ps`), plus a
   best-effort `journalctl -k`/`dmesg` scan for OOM-killer evidence.
2. **Hung / wedged minion** - process is alive but its log hasn't been
   written to in `stale_minutes` (default 20); treated as a hang.
3. **Known fatal log patterns** - dispatch timeouts, ZMQ errors, auth/
   connectivity failures to the master, etc.

In all three cases the recovery is: `kill -9` any `salt-minion`
processes, then restart the service via `systemctl` (falling back to
`service`). A restart-loop **circuit breaker** stops auto-restarting
(and just alerts instead) once `circuit_breaker.max_restarts` restarts
have happened within `circuit_breaker.window_seconds` - default 3
restarts per hour.

```yaml
salt:
  minion:
    master: salt.example.org
    master_type: str
  minion_watchdog:
    enabled: true
    cron:
      minute: '*/5'
```

- **Minion-only.** `salt.minion_watchdog` is included only when
  `salt:minion` is populated *and* `salt:minion_watchdog:enabled` is
  true - the same gate `salt.minion`/`salt.standalone` use, since it's
  protecting the local minion service this formula is managing.
- **Configurable everything** - script/log/state paths, cron schedule,
  hang threshold, extra error patterns, circuit-breaker limits, and an
  `alert_cmd` (e.g. a Slack webhook curl) run when the circuit breaker
  opens. See `pillar.example` and `defaults.yaml` for the full list.
- **Disabling it** just means leaving `salt:minion_watchdog:enabled` at
  its default `false` (or explicitly `false`) - `salt.minion_watchdog`
  then routes to `minion_watchdog/absent.sls`, which removes the script,
  cron job, and state dir if they were previously installed.

## Custom `_modules` / `_states` / `_beacons`

This fileserver root also ships custom loader extensions as top-level
`_modules/`, `_states/`, `_beacons/`, `_utils/` directories (siblings of
this `salt/` formula, not nested inside it - that's where Salt's
fileserver looks for them). `salt.sync` runs `saltutil.sync_all` on every
highstate so changes here take effect immediately instead of waiting for
the next scheduled sync.

Docker-related helpers (`dockercompose`, `docker_container`, `docker_image`,
`docker_network`, `dockerutils`) are intentionally **not** documented here -
manage those alongside whatever formula owns Docker.

| File | Type | What it does |
|------|------|-------------|
| `_states/alternatives.py` | state | Idempotent wrapper around the `alternatives` execution module (`alternatives.install` / `.remove` / `.set` / `.auto`) - the built-in `alternatives` module has no matching state module. |
| `_states/pdbedit.py` + `_modules/pdbedit.py` | state + exec | Manage Samba `passdb` accounts (`pdbedit.managed`/`pdbedit.absent`), e.g. Samba users with NT hashes, home drives, profile paths. |
| `_states/ufw.py` + `_modules/ufw.py` | state + exec | Manage UFW firewall rules (`ufw.allow`/`.deny`/`.limit`, default in/out policy, enable/disable) declaratively instead of shelling out to `ufw` in `cmd.run`. |
| `_beacons/cert_info.py` | beacon | Drop-in replacement for Salt's built-in `cert_info` beacon, rewritten against the `cryptography` package instead of the deprecated pyOpenSSL `X509Extension` API (the stock beacon is broken on current pyOpenSSL). Same config schema as the built-in beacon - see the module docstring for the full example. |
| `_modules/cert_formula_helper.py` | exec | `cert_formula_helper.get_filenames_matching_content` - finds certificate files in a directory whose contents match a given string or pillar key. |
| `_modules/convert.py` | exec | Small data-format helpers: `convert.to_json`, `convert.to_json_from_pillar_key`, `convert.to_yaml_dictionary`, `convert.to_flags`, `convert.to_list`. |
| `_modules/known_hosts_salt_ssh.py` | exec (`#!py` pillar-style module) | Builds `known_hosts` entries for `salt-ssh` targets from the roster + a trusted `known_hosts` file, exposed as `known_hosts_salt_ssh.run()`. |
| `_modules/minion_id.py` | exec | `minion_id.replace` - turns a dotted minion id into an underscore-safe string for use in SLS/pillar keys. |
| `_modules/node.py` | exec | Pillar-driven "node" helpers (`node.get`, `node.has_role`, `node.filter_by_role`, `node.resolve_network`, `node.get_routes`, ...) for sites that keep a `nodes:` pillar tree describing role/network metadata per host. |

Two real bugs were fixed while reviewing these for this refactor:

- `_states/ufw.py` used `exception.message`, which doesn't exist on Python 3
  exceptions (`AttributeError` at run time) - changed to `str(e)`.
- `_modules/node.py` imported `from salt._compat import ipaddress`, an internal Salt
  Python-2-compat shim; switched to the standard library's `ipaddress` module directly.
- `_modules/cert_formula_helper.py` called `logging.getLevelName(__name__)` where
  `logging.getLogger(__name__)` was clearly intended.

## Pillar reference

See `pillar.example` for a complete example and `defaults.yaml` for every
available key and its default value (each is commented). Highlights:

| Pillar Key | Purpose |
|-----------|---------|
| **Version pinning** | |
| `salt:version` | Exact version to install (e.g. `3008.2`), empty = latest available |
| `salt:pin_version` | Pin apt to `version_series` (default: true) |
| `salt:version_series` | APT pin version regex (default: `3008.*`) |
| **Core** | |
| `salt:install_packages` | Install salt packages via pkg.installed (default: true) |
| `salt:use_pip` | Install apache-libcloud for salt-cloud via pip (default: false) |
| `salt:rootuser` / `salt:rootgroup` | User/group for file permissions (default: root/root) |
| `salt:config_path` | Config directory (default: `/etc/salt`) |
| `salt:clean_config_d_dir` | Clean .d/ dirs before deploying (default: true) |
| `salt:parallel` / `salt:retry_options` | Git/formulas retry settings |
| **Package names** | |
| `salt:salt_master/minion/syndic/cloud/api/ssh` | Package name overrides |
| **Service details** | |
| `salt:minion_service_details` / `master_service_details` / `api_service_details` | Each has `state` (running/dead/ignore) and `enabled` (boolean). Special value `'ignore'` skips the service state entirely. |
| **Master config** | |
| `salt:master` | Written verbatim to `master.d/defaults.conf`; any Salt master setting is valid. Full template at `files/master.d/defaults.conf` (~1850 lines). Covers: primary settings, security (ACLs, LDAP auth, SSL), file server (roots, gitfs, pillar_roots, ext_pillar, s3), syndic settings, peer publish, state system, and REST API config. |
| **Minion config** | |
| `salt:minion` | Written verbatim to `minion.d/defaults.conf`; any Salt minion setting is valid. Full template at `files/minion.d/defaults.conf` (~1270 lines). Covers: connection/reconnection, grains, caching, modules, state system, file server, logging, pillar, keepalive, and proxy settings. |
| **Minion schedule** | |
| `salt:minion:schedule` | Built-in scheduler config - see "Scheduled jobs" section above for details and caveats. |
| **Extensions** | |
| `salt:extensions:enabled` | Enable extensions installation (default: true) |
| `salt:extensions:python_bin` | Bundled Python path (default: `/opt/saltstack/salt/bin/python3`) |
| `salt:extensions:build_dependencies` | apt packages needed for pip builds (e.g. libgit2-dev) |
| `salt:extensions:pip[]` | Arbitrary pip packages for bundled Python |
| `salt:extensions:saltext[]` | saltext-* packages (prefix auto-added) |
| `salt:extensions:gitfs_provider` | pygit2 \| gitpython \| dulwich \| '' (off) |
| `salt:extensions:beacon_deps:enabled` | `auto` (default, per configured beacon) \| true (full bundle) \| false |
| `salt:extensions:beacon_deps:beacon_map` | beacon name -> `{apt: [], pip: []}`; used in auto mode, merged with defaults |
| `salt:extensions:beacon_deps:apt[]` | Full-bundle apt list, used when `enabled: true` |
| `salt:extensions:beacon_deps:pip[]` | Full-bundle pip list, used when `enabled: true` |
| **SaltGUI** | |
| `salt:saltgui:enabled` | Enable SaltGUI deployment (default: false) |
| `salt:saltgui:method` | archive \| git |
| `salt:saltgui:version` | Release tag (no 'v' prefix for archive method) |
| `salt:saltgui:ref` | Git ref to track when method=git |
| `salt:saltgui:repo` | Git repo URL (default: https://github.com/erwindon/SaltGUI.git) |
| `salt:saltgui:archive_url` | Template for archive download URL |
| `salt:saltgui:target` | Install directory (default: `/srv/saltgui`) |
| `salt:saltgui:user/group` | Owner of install dir (default: root/root) |
| `salt:saltgui:nginx` | Optional nginx vhost config with `enabled`, `server_name`, `listen`, `api_backend` |
| **Exporter** | |
| `salt:exporter:enabled` | Enable salt-exporter (default: false) |
| `salt:exporter:version` | Release tag, no leading 'v' (required when enabled) |
| `salt:exporter:verify_checksum` | Verify download against checksums.txt (default: true) |
| `salt:exporter:release_base_url` | Internal mirror URL (default: GitHub releases) |
| `salt:exporter:download_url_override` / `checksums_url_override` | Exact URLs bypassing template |
| `salt:exporter:arch_map` / `arch_override` | CPU architecture mapping overrides |
| `salt:exporter:install_dir` | Binary install dir (default: `/usr/local/bin`) |
| `salt:exporter:config_dir` | Config dir (default: `/etc/salt-exporter`) |
| `salt:exporter:home_dir` | Working directory (default: `/var/lib/salt-exporter`) |
| `salt:exporter:manage_user` / `user` / `group` / `uid` / `gid` / `extra_groups` | User account settings |
| `salt:exporter:prune_old_versions` | Clean old versioned binaries |
| `salt:exporter:service:hardening_overrides` | Override systemd unit directives |
| `salt:exporter:prometheus:enabled` + `labels` | Prometheus scrape metadata |
| `salt:exporter:firewall:enabled` / `backend` / `source` / `zone` | Firewall rules per instance |
| `salt:exporter:instances:<name>` | Per-instance config with `listen_address`, `config.*`, etc. |
| **Minion Watchdog** | |
| `salt:minion_watchdog:enabled` | Enable watchdog (default: false) |
| `salt:minion_watchdog:script_path` | Script location (default: `/usr/local/bin/salt-minion-watchdog.sh`) |
| `salt:minion_watchdog:log_file` | Watchdog log file |
| `salt:minion_watchdog:minion_log_file` | Salt minion log to scan for errors |
| `salt:minion_watchdog:state_dir` | State directory (default: `/var/run/salt-minion-watchdog`) |
| `salt:minion_watchdog:cron:*` | Cron schedule fields + `identifier` |
| `salt:minion_watchdog:min_restart_interval` | Min seconds between restarts |
| `salt:minion_watchdog:stale_minutes` | Log-staleness threshold (default: 20) |
| `salt:minion_watchdog:extra_error_patterns[]` | Additional error strings to detect |
| `salt:minion_watchdog:circuit_breaker:max_restarts` / `window_seconds` | Restart loop limits |
| `salt:minion_watchdog:alert_cmd` | Alert command on circuit breaker open |
| **SSH Roster** | |
| `salt:ssh_roster` | Dict keyed by minion name with `host`, `user`, `priv`, `timeout`, `port`, etc. Written to `/etc/salt/roster`. |
| **Third-party formulas** | |
| `salt_formulas:list[]` | List of formulas to pull from git (top-level key, not under salt:) |
| `salt_formulas:git_opts.default.baseurl` / `basedir` / `update` / `options.revision/output_loglevel` | Git fetch settings for formula repos |
| **Cloud** | |
| `salt:cloud:template_sources.*` | Paths to cloud config templates (providers, profiles, maps) |
| **GitFS keys** | |
| `salt:gitfs.keys:<name>:<pub\|priv>` | SSH/GPG keys for authenticated gitfs remotes |
| **Sync** | |
| `salt:sync_custom_modules` | Run saltutil.sync_all on every highstate (default: true) |
| **Other defaults** | |
| `salt:minion:master_type` | Set to enable `salt.minion`; unset → `salt.standalone` |
| `salt:minion_remove_config` / `master_remove_config` | Remove legacy master/minion config files |
| `salt:minion_config_use_TOFS` / `master_config_use_TOFS` | Use TOFS template rendering |

## Migrating from the old ad-hoc `saltmaster.sls`

The old approach mixed formula-managed state with a hand-written
top-level `saltmaster.sls` doing `pip.installed` for `saltext-*` packages
(into the system Python - broken under onedir), a bare `salt-lint`
`pip.installed`, and the `git.latest`-of-`master` SaltGUI clone. All three
are now pillar-driven through this formula:

```yaml
salt:
  extensions:
    saltext:
      - proxmox
      - kubernetes
      - mysql
    pip:
      - salt-lint
  saltgui:
    enabled: true
```

and the `include: [nfs.server, samba, salt.cloud]` at the bottom of the
old file stays exactly as it was - those are unrelated formulas/top-file
concerns, not part of this one. (The old file's `salt-exporter` entry is
the one exception: that standalone formula has since been folded into
*this* one - see "Salt Exporter" above - so it's now `salt:exporter:
enabled: true` in pillar instead of a separate top.sls include.)

## Migrating from the standalone `salt-exporter` / `salt-minion-watchdog` formulas

Both used to be separate formulas with their own top-level pillar keys and
their own `top.sls` entries. They're now sub-states of this formula
(`salt.exporter`, `salt.minion_watchdog`), gated on master/minion context
respectively (see the include table above), so:

- Drop `- salt-exporter` / `- salt-minion-watchdog` from your `top.sls`
  (or `salt/top.sls`) - just applying `salt` now covers both, gated by
  pillar as described above.
- Rename the pillar keys and nest them under `salt:`, matching how
  `saltgui`/`extensions`/etc already work in this formula:

  ```yaml
  # old
  salt_exporter:
    version: "0.13.0"
  salt-minion-watchdog:
    enabled: true

  # new
  salt:
    exporter:
      enabled: true       # was implicit before; now required
      version: "0.13.0"
    minion_watchdog:
      enabled: true
  ```

- Every other key underneath keeps its old name (`instances`, `firewall`,
  `prometheus`, `cron`, `circuit_breaker`, ...) - only the top-level
  nesting changed. See `pillar.example` for both in full.
- File paths, systemd unit names, the script path, and the exporter
  binary/symlink locations are all unchanged, so an in-place migration
  on an already-provisioned host is just a pillar edit + re-apply, not a
  reinstall.

## Verifying a run

```bash
salt-call --local state.show_sls salt test=True   # renders without applying
salt-call --local state.apply salt test=True       # dry run
salt-call --local state.apply salt                 # apply
salt-call --local pip.list --bin_env=/opt/saltstack/salt/bin/python3   # confirm extensions landed in the right python
```


## Troubleshooting

Render and inspect changes without applying them:

```console
salt-call state.apply salt test=true
salt-call state.show_sls salt
```

Inspect the effective Salt configuration and service logs:

```console
salt-call config.get master
salt-call config.get log_file
systemctl status salt-minion salt-master salt-api --no-pager
journalctl -u salt-minion -u salt-master -u salt-api --since today
```

Validate the generated Salt configuration after a change:

```console
salt-call --local config.get file_client
salt-call --local grains.item os osrelease os_family cpuarch virtual
```

For exporter instances:

```console
systemctl list-units 'salt-exporter@*'
systemctl status salt-exporter@default
curl -fsS http://127.0.0.1:2112/metrics | head
```

For logrotate:

```console
logrotate --debug /etc/logrotate.conf
ls -l /etc/logrotate.d/salt-*
```

Common causes of an apparently skipped component are missing gating pillar
keys. Check the table under **Layout / what gets included** and verify the key
exists in the minion's compiled pillar with `salt-call pillar.get salt`.

## Documentation files

- `pillar.example` is intentionally short and safe to copy.
- `pillar.reference.sls` exposes the complete configuration surface and
  advanced examples.
- `defaults.yaml` remains the source of truth for defaults.
- `CHANGELOG.md` records operationally significant behaviour changes.

## File Layout Reference

| Path | Description |
|------|-------------|
| `init.sls` | Entry point - conditional includes based on pillar |
| `pkgrepo.sls` | Official apt repo + GPG key lifecycle management |
| `map.jinja` | Top-level map data (defaults.yaml rendering, OS detection) |
| `_mapdata/_mapdata.jinja` | Map data helper for sub-states |
| `libtofs.jinja` | TOFS (Template Override File Server) file switching helper |
| `formulas.jinja` | Third-party formula management helpers |
| `osfamilymap.yaml` / `osmap.yaml` | OS-specific value mappings |
| `master.sls` | Master package, config, service |
| `minion.sls` | Minion package, config, service, PKI |
| `standalone.sls` | Masterless minion (file_client: local) |
| `api.sls` | Salt-API (includes master first) |
| `syndic.sls` | Syndic daemon (includes master first) |
| `cloud.sls` | Cloud provisioning (packages + configs + certs) |
| `ssh.sls` | SSH roster file management |
| `extensions.sls` | Bundled Python extension installs |
| `saltgui.sls` | SaltGUI deployment (archive or git) |
| `sync.sls` | Custom module sync (`saltutil.sync_all`) |
| `unsupported.sls` | Fails loudly on unsupported OS |
| `minion_watchdog/` | Watchdog script, install, config, absent states |
| `exporter/` | Exporter binary deploy, user, config, service, firewall states |
| `files/master.d/defaults.conf` | Master config template (~1850 lines, all Salt master settings) |
| `files/minion.d/defaults.conf` | Minion config template (~1270 lines, all Salt minion settings) |
| `files/roster.jinja` | SSH roster template |
| `files/gitfs_key.jinja` | GitFS key deployment template |
| `files/cloud.providers.d/` | Cloud provider templates (EC2, Saltify, GCE, RSOS) |
| `files/cloud.profiles.d/` | Cloud profile templates |
| `files/cloud.maps.d/` | Cloud map templates |

## Relationship to upstream

**This is a heavily modified fork of
[`saltstack-formulas/salt-formula`](https://github.com/saltstack-formulas/salt-formula). Do not treat it as a drop-in
replacement for it.**

States have been renamed, split, merged, and removed; pillar keys have moved;
defaults differ; and behaviour has changed in ways that are not backward
compatible. Pointing an existing deployment at this formula without reading
`pillar.example` and the state list above will not do what you expect.

It is also not a newer version of upstream — it diverged and was maintained
separately, so upstream may well have fixes and platform support that this
does not. If you want the maintained original, use
[`saltstack-formulas/salt-formula`](https://github.com/saltstack-formulas/salt-formula).

### Credit

The foundation of this formula, and much of what still works well in it, is
the work of the [saltstack-formulas](https://github.com/saltstack-formulas) authors and contributors. Any
bugs introduced in the divergence are this fork's own.

Specific third-party files bundled here, with their own authors and
licenses, are itemised in [THIRD-PARTY.md](THIRD-PARTY.md).

## License

Dedicated to the public domain under [CC0 1.0 Universal](LICENSE), with the
exception of the third-party files listed in [THIRD-PARTY.md](THIRD-PARTY.md).
