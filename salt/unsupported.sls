# -*- coding: utf-8 -*-
# vim: ft=sls
# Fails loudly instead of silently no-op'ing on an OS this formula does not
# support, rather than pretending to manage a host it can't.

salt-formula-unsupported-os:
  test.fail_without_changes:
    - name: salt-formula-unsupported-os
    - comment: >
        This formula only supports Debian 12/13 and Ubuntu 24.04+
        (grains.os_family == 'Debian'). Detected os_family:
        '{{ grains.get("os_family", "unknown") }}',
        os: '{{ grains.get("os", "unknown") }}',
        osfinger: '{{ grains.get("osfinger", "unknown") }}'.
