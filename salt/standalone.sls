# -*- coding: utf-8 -*-
# vim: ft=sls
# Masterless ("local") minion: same package/config as minion.sls, but the
# service is intentionally kept stopped/disabled unless a master_type is
# configured (see init.sls for the logic that picks this file over
# minion.sls).

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}

include:
  - {{ tplroot }}.logrotate.minion

salt-minion-standalone:
  {%- if salt_settings.install_packages %}
  pkg.installed:
    - name: {{ salt_settings.salt_minion }}
    {%- if salt_settings.version %}
    - version: {{ salt_settings.version }}
    {%- endif %}
  {%- endif %}
  file.recurse:
    - name: {{ salt_settings.config_path }}/minion.d
    - template: jinja
    - source: salt://{{ tplroot }}/files/minion.d
    - clean: {{ salt_settings.clean_config_d_dir }}
    - exclude_pat:
      - _*
    - context:
        standalone: True
  {%- if not salt_settings.minion.master_type %}
  service.running:
    - enable: True
  {%- else %}
  service.dead:
    - enable: False
  {%- endif %}
    - name: {{ salt_settings.minion_service }}
    - require:
      {%- if salt_settings.install_packages %}
      - pkg: salt-minion-standalone
      {%- endif %}
      - file: salt-minion-standalone

# clean up old _defaults.conf file if it's still around from an earlier
# version of this formula
remove-old-standalone-conf-file:
  file.absent:
    - name: {{ salt_settings.config_path }}/minion.d/_defaults.conf
