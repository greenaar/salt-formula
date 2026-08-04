{#-
  salt.exporter.user
  ---------------------------------------------------------------------------
  Dedicated, non-root, no-shell system account the exporter binary runs as.

  NOTE: the original standalone salt-exporter formula referenced
  `salt-exporter.user` from both install.sls and config.sls but never
  actually shipped this file - the include silently no-op'd (Salt treats
  a missing `include:` target as an error at compile time, so in practice
  this only worked if something else on the box had already created the
  user out of band). Fixed here.
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/exporter/map.jinja" import se with context %}

{%- if se.manage_user %}

salt-exporter-group:
  group.present:
    - name: {{ se.group }}
    {%- if se.gid %}
    - gid: {{ se.gid }}
    {%- endif %}
    - system: True

salt-exporter-user:
  user.present:
    - name: {{ se.user }}
    - gid_from_name: False
    - gid: {{ se.group }}
    {%- if se.uid %}
    - uid: {{ se.uid }}
    {%- endif %}
    - home: {{ se.home_dir }}
    - createhome: True
    - shell: /usr/sbin/nologin
    - system: True
    {%- if se.extra_groups %}
    - groups: {{ se.extra_groups | tojson }}
    {%- endif %}
    - require:
      - group: salt-exporter-group

{%- else %}

salt-exporter-user-unmanaged:
  test.show_notification:
    - text: salt:exporter:manage_user is False - assuming '{{ se.user }}' already exists.

{%- endif %}
