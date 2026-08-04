# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}
{%- set lr = salt_settings.logrotate %}
{%- set active = [] %}
{%- set raw_salt = salt['pillar.get']('salt', {}) %}
{%- if lr.enabled %}
{%-   for component in ['minion', 'master', 'api', 'cloud'] %}
{%-     set cfg = lr.components.get(component, {}) %}
{%-     if cfg.get('enabled', false) and raw_salt.get(component) %}{%- do active.append(cfg.get('filename')) %}{%- endif %}
{%-   endfor %}
{#- The watchdog keys off salt:minion_watchdog:enabled rather than a
    populated top-level pillar section, so it does not fit the loop above. #}
{%-   set wcfg = lr.components.get('watchdog', {}) %}
{%-   if wcfg.get('enabled', false) and salt_settings.minion_watchdog.enabled %}
{%-     do active.append(wcfg.get('filename', 'salt-watchdog')) %}
{%-   endif %}
{%-   set ecfg = lr.components.get('exporter', {}) %}
{%-   if ecfg.get('enabled', false) and not ecfg.get('per_instance', true) %}
{%-     do active.append(ecfg.get('filename', 'salt-exporter')) %}
{%-   endif %}
{%- endif %}

{%- if lr.cleanup %}

{#- The salt-common package ships /etc/logrotate.d/salt-common, which
    rotates /var/log/salt/* as a group. Left in place it double-rotates
    every path the per-component snippets above own, so once this formula
    is handling rotation the packaged file is removed. Only acted on when
    logrotate handling here is enabled -- a host that has not opted in
    keeps the distro file and therefore keeps rotating. #}
{%- set salt_common = lr.get('salt_common_filename', 'salt-common') %}
{%- if lr.enabled and salt_common and '/' not in salt_common and '..' not in salt_common %}
salt-logrotate-cleanup-salt-common:
  file.absent:
    - name: {{ lr.config_dir }}/{{ salt_common }}
{%- endif %}

{%- for filename in lr.managed_filenames %}
{%-   if filename and filename not in active %}
salt-logrotate-cleanup-known-{{ filename | replace('.', '-') }}:
  file.absent:
    - name: {{ lr.config_dir }}/{{ filename }}
{%-   endif %}
{%- endfor %}

{# Remove stale per-instance exporter snippets. Current instance snippets are
   excluded. file.find executes locally during rendering and only inspects the
   tightly scoped prefix owned by this formula. #}
{%- set exporter_active = [] %}
{%- set ex = salt_settings.exporter %}
{%- set ecfg = lr.components.get('exporter', {}) %}
{%- if lr.enabled and ecfg.get('enabled', false) and ecfg.get('per_instance', true) and ex.enabled %}
{%-   for instance_name, instance in ex.instances.items() %}
{%-     if instance.get('enabled', true) and instance.get('log_file', '') %}
{%-       set ilr = instance.get('logrotate', {}) %}
{%-       if ilr.get('enabled', true) %}
{%-         do exporter_active.append(ilr.get('filename', ecfg.get('filename_prefix', lr.exporter_filename_prefix) ~ instance_name)) %}
{%-       endif %}
{%-     endif %}
{%-   endfor %}
{%- endif %}
{%- set prefix = ecfg.get('filename_prefix', lr.exporter_filename_prefix) %}
{%- for path in salt['file.find'](lr.config_dir, name=prefix ~ '*', type='f', maxdepth=1) %}
{%-   set filename = path.rsplit('/', 1)[-1] %}
{%-   if filename not in exporter_active %}
salt-logrotate-cleanup-exporter-{{ loop.index }}:
  file.absent:
    - name: {{ path }}
{%-   endif %}
{%- endfor %}
{%- endif %}
