# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}

{%- if salt_settings.logrotate.enabled %}

salt-logrotate-package:
  pkg.installed:
    - name: {{ salt_settings.logrotate.package }}

salt-logrotate-directory:
  file.directory:
    - name: {{ salt_settings.logrotate.config_dir }}
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0755'
    - makedirs: True
    - require:
      - pkg: salt-logrotate-package

{%- else %}

salt-logrotate-disabled:
  test.show_notification:
    - text: salt:logrotate:enabled is False - skipping shared logrotate setup.

{%- endif %}
