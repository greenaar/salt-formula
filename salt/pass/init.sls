{#-
  salt.pass
  ---------------------------------------------------------------------------
  Encrypted, local credential store for the Salt master, built on `pass`
  (https://www.passwordstore.org/) and GnuPG.

  Encrypted credentials live outside Pillar. Pillar carries only named
  references such as `pass:applications/roundcube/database_password`, which
  the `pass_resolver` external Pillar replaces while the master compiles
  Pillar for an authorized minion.

  Master-only by convention: salt/init.sls pulls this in when both
  `salt:master` is populated and `salt:pass:enabled` is true. The store is
  read by the master process during Pillar compilation, so it has no
  purpose on a plain minion.

  This state manages the store (packages, GPG home, key, store directory,
  the salt-secret helper) and the resolver's bootstrap config.

  That config is written to `salt:pass:master_config`, which defaults to
  master.d/_pass.conf, and is NOT rendered from pillar under `salt:master`.
  The resolver runs during pillar compilation, so pillar-derived config is
  circular: any error that stops pillar compiling also removes the
  configuration needed to repair it. The `_` prefix keeps master.sls's
  `clean: true` recurse from deleting the file. See README.md.

  See pillar.example.sls for the full pillar schema.
#}

{%- set tplroot = tpldir.split('/')[0] %}
{%- from tplroot ~ "/pass/map.jinja" import sp with context %}

{%- if not sp.enabled %}

salt-pass-disabled:
  test.show_notification:
    - text: salt:pass:enabled is False - skipping.

{%- else %}

{%- if sp.install_packages %}
salt-pass-packages:
  pkg.installed:
    - pkgs: {{ sp.packages | tojson }}
{%- endif %}

salt-pass-gpg-home:
  file.directory:
    - name: {{ sp.gpg_home }}
    - user: {{ sp.user }}
    - group: {{ sp.group }}
    - mode: '0700'
    - makedirs: True
{%- if sp.install_packages %}
    - require:
      - pkg: salt-pass-packages
{%- endif %}

salt-pass-store-directory:
  file.directory:
    - name: {{ sp.store_dir }}
    - user: {{ sp.user }}
    - group: {{ sp.group }}
    - makedirs: True
    - mode: '0700'
{%- if sp.install_packages %}
    - require:
      - pkg: salt-pass-packages
{%- endif %}

{#-
  Key creation is guarded twice, not once. The `unless` below returns
  non-zero both when the identity is genuinely absent *and* when gpg fails
  for an unrelated reason (missing binary, unreadable homedir, broken
  keyring), and on the second of those a bare `unless` would quietly mint a
  second passphrase-free key. A key that did not encrypt the store cannot
  decrypt it, so `creates` pins the state to the store's recorded identity
  file as well: once `pass init` has run, this never fires again.
#}
salt-pass-gpg-key:
  cmd.run:
    - name: >-
        gpg --batch --homedir {{ sp.gpg_home | quote }}
        --pinentry-mode loopback --passphrase '' --quick-generate-key
        {{ sp.gpg_identity | quote }} default default never
    - runas: {{ sp.user }}
    - env:
        GNUPGHOME: {{ sp.gpg_home }}
    - unless: >-
        gpg --batch --homedir {{ sp.gpg_home | quote }}
        --with-colons --list-secret-keys {{ sp.gpg_identity | quote }}
        | grep -q '^sec:'
    - creates: {{ sp.gpg_id_file | quote }}
    - require:
      - file: salt-pass-gpg-home

salt-pass-store-initialized:
  cmd.run:
    - name: pass init {{ sp.gpg_identity | quote }}
    - runas: {{ sp.user }}
    - env:
        GNUPGHOME: {{ sp.gpg_home }}
        PASSWORD_STORE_DIR: {{ sp.store_dir }}
    - unless: test -s {{ sp.gpg_id_file | quote }}
    - require:
      - cmd: salt-pass-gpg-key
      - file: salt-pass-store-directory

{#-
  Syncing the resolver is a bootstrap step, not a per-highstate one: it
  shells out to `salt-run`, which occupies a master worker thread for the
  duration and nests a job inside the running job. Both default to false;
  run `salt-run saltutil.sync_pillar` by hand after changing the module.
#}
{%- if sp.sync_pillar_resolver %}
salt-pass-pillar-resolver-synced:
  cmd.script:
    - name: salt-pass-sync-pillar-modules
    - source: salt://{{ tplroot }}/pass/files/sync-modules.sh
    - args: pillar
    - stateful: True
{%- endif %}

{%- if sp.sync_renderer %}
salt-pass-renderer-synced:
  cmd.script:
    - name: salt-pass-sync-renderers
    - source: salt://{{ tplroot }}/pass/files/sync-modules.sh
    - args: renderers
    - stateful: True
{%- endif %}

{#-
  Written unconditionally rather than watched by a service state: the
  master rereads master.d on restart, and restarting salt-master from a
  state applied by the master's own minion kills the running job, which
  never returns and is reported to the caller as a timeout. Restart out of
  band after changing these values.
#}
{%- if sp.manage_master_config %}
salt-pass-master-config:
  file.managed:
    - name: {{ sp.master_config }}
    - source: salt://{{ tplroot }}/pass/files/pass.conf.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: '0640'
    - makedirs: True
    - context:
        sp: {{ sp | tojson }}
    - require:
      - cmd: salt-pass-store-initialized
{%- endif %}

{%- if sp.manage_helper %}
salt-pass-helper:
  file.managed:
    - name: {{ sp.helper_path }}
    - source: salt://{{ tplroot }}/pass/files/salt-secret.jinja
    - template: jinja
    - user: root
    - group: {{ sp.group }}
    - mode: '0750'
    - context:
        sp: {{ sp | tojson }}
    - require:
      - cmd: salt-pass-store-initialized
{%- endif %}

{%- endif %}
