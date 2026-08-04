# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}
{%- set cfg = salt_settings.logrotate.components.watchdog %}

{#- The watchdog log lives outside /var/log/salt and its location is owned
    by salt:minion_watchdog:log_file. Default to that value so enabling
    rotation never targets a stale path; an explicit
    salt:logrotate:components:watchdog:paths still wins. #}
{%- set mw = salt_settings.minion_watchdog %}
{%- set rendered_cfg = cfg.copy() %}
{%- if not cfg.get('paths') %}
{%-   do rendered_cfg.update({'paths': [mw.log_file] if mw.get('log_file') else []}) %}
{%- endif %}

{#- Also gated on the watchdog itself: when minion_watchdog is disabled its
    log is no longer written, so the snippet is removed rather than left
    rotating a file nothing produces. #}
{%- if salt_settings.logrotate.enabled and cfg.enabled and mw.enabled and rendered_cfg.paths %}
include:
  - {{ tplroot }}.logrotate

salt-logrotate-watchdog:
  file.managed:
    - name: {{ salt_settings.logrotate.config_dir }}/{{ cfg.filename }}
    - source: salt://{{ tplroot }}/logrotate/files/component.jinja
    - template: jinja
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0644'
    - context:
        tplroot: {{ tplroot }}
        component: watchdog
        settings: {{ rendered_cfg | tojson }}
    - require:
      - file: salt-logrotate-directory
{%- if salt_settings.logrotate.validate %}
    - check_cmd: {{ salt_settings.logrotate.validate_command }}
{%- endif %}
{%- else %}
salt-logrotate-watchdog-absent:
  file.absent:
    - name: {{ salt_settings.logrotate.config_dir }}/{{ cfg.filename }}
{%- endif %}
