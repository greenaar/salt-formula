# -*- coding: utf-8 -*-
# vim: ft=sls
#
# Syncs custom _modules/_states/_beacons/_utils (this formula ships several
# - see README.md) out to the minion applying this state, so they're
# available without waiting for the next scheduled sync or a manual
# `saltutil.sync_all`. Cheap to run every highstate.

sync-custom-modules:
  module.run:
    - name: saltutil.sync_all
    - refresh: True
