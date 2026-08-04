# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/exporter/map.jinja" import se with context %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}
{%- set cfg = salt_settings.logrotate.components.exporter %}

{%- if salt_settings.logrotate.enabled and cfg.enabled %}
include:
  - {{ tplroot }}.logrotate

{%- if cfg.get('per_instance', true) %}
{%- for instance_name, instance in se.instances.items() %}
{%- set instance_lr = instance.get('logrotate', {}) %}
{%- if instance.get('enabled', true) and instance.get('log_file', '') and instance_lr.get('enabled', true) %}
{%- set rendered_cfg = cfg.copy() %}
{%- do rendered_cfg.update(instance_lr) %}
{%- do rendered_cfg.update({
      'filename': instance_lr.get('filename', cfg.get('filename_prefix', 'salt-exporter-') ~ instance_name),
      'paths': [instance.get('log_file')]
    }) %}

salt-logrotate-exporter-{{ instance_name }}:
  file.managed:
    - name: {{ salt_settings.logrotate.config_dir }}/{{ rendered_cfg.filename }}
    - source: salt://{{ tplroot }}/logrotate/files/component.jinja
    - template: jinja
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0644'
    - context:
        tplroot: {{ tplroot }}
        component: exporter-{{ instance_name }}
        settings: {{ rendered_cfg | tojson }}
    - require:
      - file: salt-logrotate-directory
{%- if salt_settings.logrotate.validate %}
    - check_cmd: {{ salt_settings.logrotate.validate_command }}
{%- endif %}
{%- endif %}
{%- endfor %}
{%- else %}
{%- set ns = namespace(paths=[]) %}
{%- for instance_name, instance in se.instances.items() %}
{%-   if instance.get('enabled', true) and instance.get('log_file', '') %}
{%-     do ns.paths.append(instance.get('log_file')) %}
{%-   endif %}
{%- endfor %}
{%- if ns.paths %}
{%- set rendered_cfg = cfg.copy() %}
{%- do rendered_cfg.update({'paths': ns.paths}) %}
salt-logrotate-exporter:
  file.managed:
    - name: {{ salt_settings.logrotate.config_dir }}/{{ cfg.filename }}
    - source: salt://{{ tplroot }}/logrotate/files/component.jinja
    - template: jinja
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0644'
    - context:
        tplroot: {{ tplroot }}
        component: exporter
        settings: {{ rendered_cfg | tojson }}
    - require:
      - file: salt-logrotate-directory
{%- if salt_settings.logrotate.validate %}
    - check_cmd: {{ salt_settings.logrotate.validate_command }}
{%- endif %}
{%- endif %}
{%- endif %}
{%- endif %}
