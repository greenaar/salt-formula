{#-
  salt.exporter
  ---------------------------------------------------------------------------
  Installs and configures salt-exporter (https://kpetremann.github.io/salt-exporter/)
  - a Prometheus exporter for salt-master job/event metrics - from a
  versioned GitHub (or internal mirror) release, never from source.

  Master-only by convention: salt/init.sls only pulls this in when both
  `salt:master` is populated and `salt:exporter:enabled` is true, since
  the exporter reads the local salt-master's event bus. Applying
  `salt.exporter` directly on a host with no local master will still
  work mechanically, but the exporter will have nothing to read.

  Entry point. Include this state (`- salt.exporter`) to get everything:
  user, versioned install with checksum-verified download, per-instance
  config, and hardened systemd services. Firewall rules are pulled in
  automatically by service.sls when salt:exporter:firewall:enabled is set.

  See pillar.example.sls for the full pillar schema and README.md for the
  full write-up (hardening details, multi-instance, internal mirrors...).
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/exporter/map.jinja" import se with context %}

{%- if se.enabled %}

include:
  - {{ tplroot }}.exporter.install
  - {{ tplroot }}.exporter.config
  - {{ tplroot }}.exporter.service
  - {{ tplroot }}.exporter.logrotate

{%- else %}

salt-exporter-disabled:
  test.show_notification:
    - text: salt:exporter:enabled is False - skipping.

{%- endif %}
