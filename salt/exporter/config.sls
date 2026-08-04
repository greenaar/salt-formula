{#-
  salt.exporter.config
  ---------------------------------------------------------------------------
  Renders <config_dir>/<instance>/config.yaml and exporter.env for every
  instance defined in pillar. Nothing here is hardcoded - the whole
  config.yaml body is whatever dict you put under
  salt:exporter:instances:<name>:config.
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/exporter/map.jinja" import se with context %}

include:
  - {{ tplroot }}.exporter.user

salt-exporter-config-root:
  file.directory:
    - name: {{ se.config_root }}
    - user: root
    - group: {{ se.group }}
    - mode: '0750'
    - makedirs: True

{%- for instance_name, instance in se.instances.items() %}
{%- if instance.get('enabled', True) %}

salt-exporter-instance-dir-{{ instance_name }}:
  file.directory:
    - name: {{ se.config_root }}/{{ instance_name }}
    - user: root
    - group: {{ se.group }}
    - mode: '0750'
    - require:
      - file: salt-exporter-config-root

salt-exporter-config-{{ instance_name }}:
  file.managed:
    - name: {{ se.config_root }}/{{ instance_name }}/config.yaml
    - source: salt://{{ tplroot }}/exporter/files/config.yaml.jinja
    - template: jinja
    - user: root
    - group: {{ se.group }}
    - mode: '0640'
    - context:
        instance_name: {{ instance_name }}
        instance_config: {{ instance.get('config', {}) | tojson }}
    - require:
      - file: salt-exporter-instance-dir-{{ instance_name }}

salt-exporter-env-{{ instance_name }}:
  file.managed:
    - name: {{ se.config_root }}/{{ instance_name }}/exporter.env
    - source: salt://{{ tplroot }}/exporter/files/exporter.env.jinja
    - template: jinja
    - user: root
    - group: {{ se.group }}
    - mode: '0640'
    - context:
        instance_name: {{ instance_name }}
        instance: {{ instance | tojson }}
    - require:
      - file: salt-exporter-instance-dir-{{ instance_name }}

{%- if instance.get('log_file', '') %}
{%- set log_cfg = se.log.copy() %}
{%- do log_cfg.update(instance.get('log', {})) %}
{%- set log_dir = instance.get('log_file').rsplit('/', 1)[0] %}
{%- if log_cfg.get('manage_directory', true) %}
salt-exporter-log-dir-{{ instance_name }}:
  file.directory:
    - name: {{ log_dir }}
    - user: {{ log_cfg.get('directory_user') or se.user }}
    - group: {{ log_cfg.get('directory_group') or se.group }}
    - mode: '{{ log_cfg.get('directory_mode', '0750') }}'
    - makedirs: True
{%- endif %}

{%- if log_cfg.get('manage_file', true) %}
salt-exporter-log-file-{{ instance_name }}:
  file.managed:
    - name: {{ instance.get('log_file') }}
    - user: {{ log_cfg.get('file_user') or se.user }}
    - group: {{ log_cfg.get('file_group') or se.group }}
    - mode: '{{ log_cfg.get('file_mode', '0640') }}'
    - replace: False
{%- if log_cfg.get('manage_directory', true) %}
    - require:
      - file: salt-exporter-log-dir-{{ instance_name }}
{%- endif %}
{%- endif %}
{%- endif %}

{%- if instance.get('state_dir', '') %}
salt-exporter-state-dir-{{ instance_name }}:
  file.directory:
    - name: {{ instance['state_dir'] }}
    - user: {{ se.user }}
    - group: {{ se.group }}
    - mode: '0750'
    - makedirs: True
{%- endif %}

{%- endif %}
{%- endfor %}
