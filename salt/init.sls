# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings, is_supported_os with context %}

{%- if not is_supported_os %}

include:
  - salt.unsupported

{%- else %}

include:
  - salt.pkgrepo
  - salt.logrotate.cleanup
      {%- if salt.config.get('salt_formulas:list') %}
  - salt.formulas
      {%- endif %}
      {%- if salt.config.get('salt:master')|length > 1 %}
  - salt.master
      {%- endif %}
      {%- if salt.config.get('salt:master')|length > 1 and salt_settings.exporter.enabled %}
  - salt.exporter
      {%- endif %}
      {%- if salt.config.get('salt:master')|length > 1 and salt_settings.pass.enabled %}
  - salt.pass
      {%- endif %}
      {%- if salt.config.get('salt:cloud')|length > 1 %}
  - salt.cloud
      {%- endif %}
      {%- if salt.config.get('salt:ssh_roster') %}
  - salt.ssh
      {%- endif %}
      {%- if salt.config.get('salt:minion')|length > 1 %}
          {%- if salt.config.get('salt:minion:master_type') %}
  - salt.minion
          {%- else %}
  - salt.standalone
          {%- endif %}
      {%- endif %}
      {%- if salt.config.get('salt:minion')|length > 1 and salt_settings.minion_watchdog.enabled %}
  - salt.minion_watchdog
      {%- endif %}
      {%- if salt.config.get('salt:api') %}
  - salt.api
      {%- endif %}
      {%- if salt.config.get('salt:syndic') %}
  - salt.syndic
      {%- endif %}
      {%- if salt_settings.extensions.enabled %}
  - salt.extensions
      {%- endif %}
      {%- if salt_settings.saltgui.enabled %}
  - salt.saltgui
      {%- endif %}
      {%- if salt_settings.sync_custom_modules %}
  - salt.sync
      {%- endif %}

{%- endif %}
