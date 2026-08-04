{#-
  salt.exporter.service
  ---------------------------------------------------------------------------
  One systemd unit per configured instance:
    /etc/systemd/system/salt-exporter-<instance>.service

  The unit only restarts when something that actually matters changed:
  the resolved binary (symlink target), the rendered config.yaml, the
  env file with CLI flags, or the unit file itself.
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/exporter/map.jinja" import se with context %}

include:
  - {{ tplroot }}.exporter.install
  - {{ tplroot }}.exporter.config
  {%- if se.firewall.get('enabled', False) %}
  - {{ tplroot }}.exporter.firewall
  {%- endif %}

salt-exporter-systemd-dir:
  file.directory:
    - name: /etc/systemd/system
    - makedirs: True

{%- for instance_name, instance in se.instances.items() %}
{%- if instance.get('enabled', True) %}

{%- set listen_address = instance.get('listen_address', '0.0.0.0:2112') %}
{%- set listen_port = listen_address.rsplit(':', 1)[-1] %}
{%- set instance_ctx = instance.copy() %}
{%- do instance_ctx.update({'_listen_port': listen_port}) %}

salt-exporter-unit-{{ instance_name }}:
  file.managed:
    - name: /etc/systemd/system/salt-exporter-{{ instance_name }}.service
    - source: salt://{{ tplroot }}/exporter/files/salt-exporter.service.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        instance_name: {{ instance_name }}
        instance: {{ instance_ctx | tojson }}
        se: {{ se | tojson }}
    - require:
      - file: salt-exporter-systemd-dir

salt-exporter-reload-{{ instance_name }}:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: salt-exporter-unit-{{ instance_name }}

salt-exporter-service-{{ instance_name }}:
  service.running:
    - name: salt-exporter-{{ instance_name }}
    - enable: True
    - require:
      - cmd: salt-exporter-reload-{{ instance_name }}
    - watch:
      - file: salt-exporter-unit-{{ instance_name }}
      - file: salt-exporter-config-{{ instance_name }}
      - file: salt-exporter-env-{{ instance_name }}
      - file: salt-exporter-symlink

{%- else %}

{#- Instance explicitly disabled in pillar: make sure it's stopped and
    disabled rather than silently left running from a previous highstate. #}
salt-exporter-service-{{ instance_name }}-disabled:
  service.dead:
    - name: salt-exporter-{{ instance_name }}
    - enable: False

{%- endif %}
{%- endfor %}
