# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}
{%- from tplroot ~ "/libtofs.jinja" import files_switch with context %}

include:
  - {{ tplroot }}.logrotate.minion

salt-minion:
  {%- if salt_settings.install_packages %}
  pkg.installed:
    - name: {{ salt_settings.salt_minion }}
    {%- if salt_settings.version %}
    - version: {{ salt_settings.version }}
    {%- endif %}
    {%- if salt_settings.minion_service_details.state != 'ignore' %}
    - require_in:
      - service: salt-minion
    {%- endif %}
  {%- endif %}
  file.recurse:
    - name: {{ salt_settings.config_path }}/minion.d
    {%- if salt_settings.minion_config_use_TOFS %}
    - template: ''
    - source: {{ files_switch(['minion.d'], lookup='salt-minion') }}
    {%- else %}
    - template: jinja
    - source: salt://{{ tplroot }}/files/minion.d
    - context:
        standalone: False
    {%- endif %}
    - clean: {{ salt_settings.clean_config_d_dir }}
    - exclude_pat:
      - _*
  {%- if salt_settings.minion_service_details.state != 'ignore' %}
  service.{{ salt_settings.minion_service_details.state }}:
    - enable: {{ salt_settings.minion_service_details.enabled }}
    - name: {{ salt_settings.minion_service }}
    - watch:
      - file: salt-minion
      - file: remove-old-minion-conf-file
    - order: last
  {%- endif %}

{%- if salt_settings.minion_remove_config %}

remove-default-minion-conf-file:
  file.absent:
    - name: {{ salt_settings.config_path }}/minion
{%- else %}

permissions-minion-config:
  file.managed:
    - name: {{ salt_settings.config_path }}/minion
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0640'
    - replace: False
{%- endif %}

# clean up old _defaults.conf file if it's still around from an earlier
# version of this formula
remove-old-minion-conf-file:
  file.absent:
    - name: {{ salt_settings.config_path }}/minion.d/_defaults.conf

salt-minion-pki-dir:
  file.directory:
    - name: {{ salt_settings.minion.get('pki_dir', salt_settings.config_path ~ '/pki/minion') }}
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0700'
    - makedirs: True

permissions-minion.pem:
  file.managed:
    - name: {{ salt_settings.minion.get('pki_dir', salt_settings.config_path ~ '/pki/minion') }}/minion.pem
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0400'
    - replace: False
    - require:
      - file: salt-minion-pki-dir

permissions-minion.pub:
  file.managed:
    - name: {{ salt_settings.minion.get('pki_dir', salt_settings.config_path ~ '/pki/minion') }}/minion.pub
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0644'
    - replace: False
    - require:
      - file: salt-minion-pki-dir
