# -*- coding: utf-8 -*-
# vim: ft=sls

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}

include:
  - {{ tplroot }}.logrotate.cloud

{%- if salt_settings.use_pip %}
salt-cloud-python3-pip:
  pkg.installed:
    - name: python3-pip

salt-cloud-pip-packages:
  pip.installed:
    - pkgs:
      - apache-libcloud
    - bin_env: {{ salt_settings.extensions.python_bin }}
    - require:
      - pkg: salt-cloud-python3-pip
{%- endif %}

{%- if salt_settings.install_packages %}
salt-cloud:
  pkg.installed:
    - name: {{ salt_settings.salt_cloud }}
    {%- if salt_settings.version %}
    - version: {{ salt_settings.version }}
    {%- endif %}
    {%- if salt_settings.use_pip %}
    - require:
      - pip: salt-cloud-pip-packages
    {%- endif %}
{%- endif %}

{%- for cert in pillar.get('salt_cloud_certs', {}) %}
cloud-cert-{{ cert }}-pem:
  file.managed:
    - name: {{ salt_settings.config_path }}/pki/cloud/{{ cert }}.pem
    - source: salt://{{ tplroot }}/files/key
    - template: jinja
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0600'
    - makedirs: True
    - defaults:
        key: {{ cert }}
        type: pem
{%- endfor %}

{%- set cloud_pillar = salt['pillar.get']('salt', {}, unmask=True) %}
{%- for cloud_section in ["maps", "profiles", "providers"] %}
salt-cloud-{{ cloud_section }}:
  file.recurse:
    - name: {{ salt_settings.config_path }}/cloud.{{ cloud_section }}.d
    - source: {{ salt_settings.cloud.template_sources[cloud_section] }}
    - template: jinja
    - makedirs: True
    - exclude_pat: _*

  {%- set section_data = cloud_pillar.get('cloud', {}).get(cloud_section, {}) %}
  {%- for filename, filedata in section_data.items() %}
salt-cloud-{{ cloud_section }}-{{ filename }}:
  file.serialize:
    - name: {{ salt_settings.config_path }}/cloud.{{ cloud_section }}.d/{{ filename }}
    - dataset: {{ filedata | tojson }}
    - formatter: yaml
    - require:
      - file: salt-cloud-{{ cloud_section }}
    {%- if cloud_section == "providers" %}
    - require_in:
      - file: salt-cloud-providers-permissions
    {%- endif %}
  {%- endfor %}
{%- endfor %}

salt-cloud-providers-permissions:
  file.directory:
    - name: {{ salt_settings.config_path }}/cloud.providers.d
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - file_mode: 600
    - dir_mode: 700
    - recurse:
      - user
      - group
      - mode
    - require:
      - file: salt-cloud-providers
