{#-
  salt.minion_watchdog.install
  ---------------------------------------------------------------------------
  Installs the salt-minion-watchdog script and (optionally) its cron job.
  Included by init.sls when salt:minion_watchdog:enabled is true.
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/minion_watchdog/map.jinja" import mw with context %}

salt-minion-watchdog-statedir:
  file.directory:
    - name: {{ mw.state_dir }}
    - user: root
    - group: root
    - mode: '0750'
    - makedirs: True

salt-minion-watchdog-script:
  file.managed:
    - name: {{ mw.script_path }}
    - source: salt://{{ tplroot }}/minion_watchdog/files/salt-minion-watchdog.sh.jinja
    - template: jinja
    - context:
        tplroot: {{ tplroot }}
    - user: root
    - group: root
    - mode: '0750'
    - makedirs: True
    - require:
      - file: salt-minion-watchdog-statedir

{%- if mw.cron.enabled %}
salt-minion-watchdog-cron:
  cron.present:
    - name: {{ mw.script_path }} >> {{ mw.log_file }} 2>&1
    - identifier: {{ mw.cron.identifier }}
    - user: {{ mw.cron.user }}
    - minute: "{{ mw.cron.minute }}"
    - hour: "{{ mw.cron.hour }}"
    - daymonth: "{{ mw.cron.daymonth }}"
    - month: "{{ mw.cron.month }}"
    - dayweek: "{{ mw.cron.dayweek }}"
    - require:
      - file: salt-minion-watchdog-script
{%- else %}
salt-minion-watchdog-cron-disabled:
  cron.absent:
    - name: {{ mw.script_path }} >> {{ mw.log_file }} 2>&1
    - identifier: {{ mw.cron.identifier }}
    - user: {{ mw.cron.user }}
{%- endif %}
