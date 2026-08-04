{#-
  salt.minion_watchdog.absent
  ---------------------------------------------------------------------------
  Removes the salt-minion-watchdog script, its cron job, and its state
  directory. Included by init.sls when salt:minion_watchdog:enabled is
  false. Can also be applied directly:

      salt '*' state.apply salt.minion_watchdog.absent
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/minion_watchdog/map.jinja" import mw with context %}

salt-minion-watchdog-cron-removed:
  cron.absent:
    - name: {{ mw.script_path }} >> {{ mw.log_file }} 2>&1
    - identifier: {{ mw.cron.identifier }}
    - user: {{ mw.cron.user }}

salt-minion-watchdog-script-removed:
  file.absent:
    - name: {{ mw.script_path }}
    - require:
      - cron: salt-minion-watchdog-cron-removed

salt-minion-watchdog-statedir-removed:
  file.absent:
    - name: {{ mw.state_dir }}
