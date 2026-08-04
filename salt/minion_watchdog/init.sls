{#-
  salt.minion_watchdog
  ---------------------------------------------------------------------------
  Installs (or removes) a cron-driven watchdog script that detects and
  recovers from unhealthy salt-minion processes:

    1. Crash / OOM-kill -- process-existence check (pgrep/ps), plus a
       best-effort journalctl -k / dmesg scan for OOM-killer evidence.
    2. Hung / wedged minion -- process is alive but its log hasn't been
       written to in stale_minutes (default 20); treated as a hang.
    3. Known fatal log patterns -- dispatch timeouts, ZMQ errors, auth /
       connectivity failures to the master, etc.

  In all three cases the recovery is: kill -9 any salt-minion processes,
  then restart the service via systemctl (falling back to service).

  A restart-loop circuit breaker stops auto-restarting (and just alerts
  instead) once circuit_breaker.max_restarts restarts have happened
  within circuit_breaker.window_seconds -- default 3 restarts per hour.

  Minion-only by convention: salt/init.sls only pulls this in when both
  `salt:minion` is populated and `salt:minion_watchdog:enabled` is true -
  the same gate salt.minion/salt.standalone use - since it protects the
  local salt-minion service this formula is managing.

  Apply directly with:
      salt '*' state.apply salt.minion_watchdog

  Routes to install.sls or absent.sls based on
  salt:minion_watchdog:enabled (default: false, see defaults.yaml).
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/minion_watchdog/map.jinja" import mw with context %}

include:
{%- if mw.enabled %}
  - {{ tplroot }}.minion_watchdog.install
{%- else %}
  - {{ tplroot }}.minion_watchdog.absent
{%- endif %}
{#- Included on both branches: salt.logrotate.watchdog writes the snippet
    when the watchdog is enabled and removes it when it is not. #}
  - {{ tplroot }}.logrotate.watchdog
