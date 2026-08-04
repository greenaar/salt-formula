{#-
  salt.exporter.firewall
  ---------------------------------------------------------------------------
  Opt-in only (salt:exporter:firewall:enabled: True). Opens the listen
  port for every enabled instance via either ufw or firewalld. Neither
  the ufw nor firewalld states install/enable the firewall service
  itself - they assume you already manage that elsewhere - this only
  adds the rule(s).
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/exporter/map.jinja" import se with context %}

{%- set backend = se.firewall.get('backend', 'ufw') %}
{%- set source = se.firewall.get('source', None) %}

{%- for instance_name, instance in se.instances.items() %}
{%- if instance.get('enabled', True) %}
{%- set listen_address = instance.get('listen_address', '0.0.0.0:2112') %}
{%- set listen_port = listen_address.rsplit(':', 1)[-1] %}

{%- if backend == 'ufw' %}
salt-exporter-ufw-{{ instance_name }}:
  cmd.run:
    - name: >
        ufw allow
        {%- if source %} from {{ source }}{% endif %}
        to any port {{ listen_port }} proto tcp
        comment 'salt-exporter ({{ instance_name }})'
    - unless: >
        ufw status | grep -qE '^{{ listen_port }}/tcp.*ALLOW'

{%- elif backend == 'firewalld' %}
salt-exporter-firewalld-{{ instance_name }}:
  firewalld.present:
    - name: {{ se.firewall.get('zone', 'public') }}
    - ports:
      - {{ listen_port }}/tcp
    {%- if source %}
    - rich_rules:
      - 'rule family="ipv4" source address="{{ source }}" port port="{{ listen_port }}" protocol="tcp" accept'
    {%- endif %}

{%- else %}
salt-exporter-firewall-unsupported-{{ instance_name }}:
  test.fail_without_changes:
    - name: >
        salt:exporter:firewall:backend '{{ backend }}' is not supported
        (expected 'ufw' or 'firewalld')
{%- endif %}

{%- endif %}
{%- endfor %}
