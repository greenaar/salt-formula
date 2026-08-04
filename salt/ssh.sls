# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}

{%- if salt_settings.install_packages %}
ensure-salt-ssh-is-installed:
  pkg.installed:
    - name: {{ salt_settings.salt_ssh }}
    {%- if salt_settings.version %}
    - version: {{ salt_settings.version }}
    {%- endif %}
{%- endif %}

ensure-roster-config:
  file.managed:
    - name: {{ salt_settings.config_path }}/roster
    - source: salt://{{ tplroot }}/files/roster.jinja
    - template: jinja
    {%- if salt_settings.install_packages %}
    - require:
      - pkg: ensure-salt-ssh-is-installed
    {%- endif %}
