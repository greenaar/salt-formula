# -*- coding: utf-8 -*-
# vim: ft=sls
# Deploys SSH keys for authenticated gitfs/git_pillar remotes, from
# `salt:gitfs:keys:<name>:<pub|priv>`. Independent of which gitfs provider
# (pygit2/gitpython/dulwich) is installed via extensions.sls.

{%- from "salt/map.jinja" import salt_settings with context %}

{%- set gitfs_keys = salt_settings.gitfs.get('keys', {}) %}

{%- for key, keyvalues in gitfs_keys.items() %}
{%- for type, keydata in keyvalues.items() %}
gitfs-key-{{ key }}-{{ type }}:
  file.managed:
    - name: {{ salt_settings.config_path }}/pki/gitfs/{{ key }}.{{ type }}
    - source: salt://salt/files/gitfs_key.jinja
    - template: jinja
    - user: {{ salt_settings.rootuser }}
    - group: {{ salt_settings.rootgroup }}
    - mode: '0600'
    - makedirs: True
    - defaults:
        key: {{ key }}
        type: {{ type }}
{%- endfor %}
{%- endfor %}
