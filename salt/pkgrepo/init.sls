# -*- coding: utf-8 -*-
# vim: ft=sls
{% from "salt/map.jinja" import salt_settings with context %}

  {%- if salt_settings.pkgrepo and salt_settings.use_pkgrepo %}

include:
  - .{{ grains['os_family']|lower }}

  {%- endif %}
