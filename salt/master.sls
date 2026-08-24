# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}
{%- from tplroot ~ "/libtofs.jinja" import files_switch with context %}
{%- from tplroot ~ "/libconfd.jinja" import confd_exclude_pat with context %}

include:
  - {{ tplroot }}.logrotate.master
{%- if salt_settings.gitfs.get('keys') %}
  - {{ tplroot }}.gitfs.keys
{%- endif %}

salt-master:
  {%- if salt_settings.install_packages %}
  pkg.installed:
    - name: {{ salt_settings.salt_master }}
    {%- if salt_settings.version %}
    - version: {{ salt_settings.version }}
    {%- endif %}
    {%- if salt_settings.master_service_details.state != 'ignore' %}
    - require_in:
      - service: salt-master
    - watch_in:
      - service: salt-master
    {%- endif %}
  {%- endif %}
  file.recurse:
    - name: {{ salt_settings.config_path }}/master.d
    {%- if salt_settings.master_config_use_TOFS %}
    - template: ''
    - source: {{ files_switch(['master.d'], lookup='salt-master') }}
    {%- else %}
    - template: jinja
    - source: salt://{{ tplroot }}/files/master.d
    {%- endif %}
    - clean: {{ salt_settings.clean_config_d_dir }}
    {#- Protects both from deployment and from `clean`. Built from
        salt:config_d_preserve, the config files other formulas declare in
        their own pillar, and salt:master_config_d_preserve. See
        libconfd.jinja. #}
    - exclude_pat: {{ confd_exclude_pat(salt_settings, 'master') }}
  {%- if salt_settings.master_service_details.state != 'ignore' %}
  service.{{ salt_settings.master_service_details.state }}:
    - enable: {{ salt_settings.master_service_details.enabled }}
    - name: {{ salt_settings.master_service }}
    - watch:
      - file: salt-master
      - file: remove-old-master-conf-file
    - order: last
  {%- endif %}

{%- if salt_settings.master_remove_config %}

remove-default-master-conf-file:
  file.absent:
    - name: {{ salt_settings.config_path }}/master
    - watch_in:
      - service: salt-master
{%- endif %}

# clean up old _defaults.conf file if it's still around from an earlier
# version of this formula
remove-old-master-conf-file:
  file.absent:
    - name: {{ salt_settings.config_path }}/master.d/_defaults.conf
