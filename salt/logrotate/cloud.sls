# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}
{%- set cfg = salt_settings.logrotate.components.cloud %}

{%- if salt_settings.logrotate.enabled and cfg.enabled %}
include:
  - {{ tplroot }}.logrotate

salt-logrotate-cloud:
  file.managed:
    - name: {{ salt_settings.logrotate.config_dir }}/{{ cfg.filename }}
    - source: salt://{{ tplroot }}/logrotate/files/component.jinja
    - template: jinja
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0644'
    - context:
        tplroot: {{ tplroot }}
        component: cloud
        settings: {{ cfg | tojson }}
    - require:
      - file: salt-logrotate-directory
{%- if salt_settings.logrotate.validate %}
    - check_cmd: {{ salt_settings.logrotate.validate_command }}
{%- endif %}
{%- else %}
salt-logrotate-cloud-absent:
  file.absent:
    - name: {{ salt_settings.logrotate.config_dir }}/{{ cfg.filename }}
{%- endif %}
