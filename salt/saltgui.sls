# -*- coding: utf-8 -*-
# vim: ft=sls
#
# SaltGUI (https://github.com/erwindon/SaltGUI) is a static single-page app
# that talks to salt-api's rest_cherrypy endpoint. This deploys it two ways:
#
#   method: archive (default, recommended) - downloads a pinned release
#   tarball. This is what actually fixes the old approach of `git.latest`
#   tracking the `master` branch forever: every highstate could silently
#   pull in unreviewed upstream changes, and a shallow clone with no pinned
#   ref is not reproducible across hosts.
#
#   method: git - kept for people who deliberately want to track a branch;
#   pin `salt:saltgui:ref` to a tag if you want this to be reproducible too.
#
# This state only deploys the static files (+ optional nginx vhost). It
# does not stand up salt-api itself - see the `salt.api` state and
# `salt:api` pillar keys for that, and make sure rest_cherrypy has CORS
# enabled for whatever origin SaltGUI is served from.
#
# State IDs below are all namespaced (salt-saltgui-*) rather than using the
# bare target paths as IDs - state IDs are global across the whole compiled
# highstate, so a literal path like `/etc/nginx/sites-available/foo.conf`
# or a bare `nginx:` will collide the moment another formula in the same
# run happens to touch the same path/name.

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/map.jinja" import salt_settings with context %}

{%- set gui = salt_settings.saltgui %}

{%- if gui.enabled %}

salt-saltgui-target-dir:
  file.directory:
    - name: {{ gui.target }}
    - user: {{ gui.user }}
    - group: {{ gui.group }}
    - makedirs: True

{%- if gui.method == 'git' %}

saltgui-deploy:
  git.latest:
    - name: {{ gui.repo }}
    - target: {{ gui.target }}
    - rev: {{ gui.ref }}
    - user: {{ gui.user }}
    - require:
      - file: salt-saltgui-target-dir

{%- else %}

{%- set archive_url = gui.archive_url.replace('{version}', gui.version) %}

saltgui-deploy:
  archive.extracted:
    - name: {{ gui.target }}
    - source: {{ archive_url }}
    - skip_verify: True
    - archive_format: tar
    - options: '--strip-components=1'
    - enforce_toplevel: False
    - if_missing: {{ gui.target }}/index.html
    - user: {{ gui.user }}
    - group: {{ gui.group }}
    - require:
      - file: salt-saltgui-target-dir

{%- endif %}

{%- if gui.nginx.enabled %}

salt-saltgui-nginx-pkg:
  pkg.installed:
    - name: nginx

salt-saltgui-nginx-site-available:
  file.managed:
    - name: /etc/nginx/sites-available/{{ gui.nginx.server_name }}.conf
    - contents: |
        server {
            listen {{ gui.nginx.listen }};
            server_name {{ gui.nginx.server_name }};

            root {{ gui.target }};
            index index.html;

            location / {
                try_files $uri $uri/ /index.html;
            }

            # Proxy SaltGUI's API calls through to salt-api (rest_cherrypy).
            # SaltGUI expects the API reachable at the same origin under /.
            location ~ ^/(login|logout|minions|jobs|keys|run|events|ws)($|/) {
                proxy_pass {{ gui.nginx.api_backend }};
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_http_version 1.1;
                proxy_set_header Connection "";
            }
        }
    - require:
      - pkg: salt-saltgui-nginx-pkg

salt-saltgui-nginx-site-enabled:
  file.symlink:
    - name: /etc/nginx/sites-enabled/{{ gui.nginx.server_name }}.conf
    - target: /etc/nginx/sites-available/{{ gui.nginx.server_name }}.conf
    - require:
      - file: salt-saltgui-nginx-site-available

salt-saltgui-nginx-service:
  service.running:
    - name: nginx
    - enable: True
    - watch:
      - file: salt-saltgui-nginx-site-available
      - file: salt-saltgui-nginx-site-enabled
{%- endif %}

{%- else %}

saltgui-disabled:
  test.show_notification:
    - text: salt:saltgui:enabled is False - skipping.

{%- endif %}
