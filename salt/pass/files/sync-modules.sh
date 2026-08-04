#!/bin/sh

# Emit Salt's stateful command protocol so a no-op sync is not reported as a
# change. Only the module types used by this formula are accepted.
set -eu

case "${1:-}" in
  pillar)
    label='Pillar modules'
    ;;
  renderers)
    label='Renderers'
    ;;
  *)
    echo "Unsupported Salt module type: ${1:-missing}" >&2
    exit 64
    ;;
esac

result="$(salt-run --out=json --out-indent=-1 "saltutil.sync_$1")"
compact="$(printf '%s' "$result" | tr -d '[:space:]')"

if [ -z "$compact" ] || [ "$compact" = '[]' ] || \
   [ "$compact" = '{}' ] || [ "$compact" = 'null' ]; then
  printf "changed=no comment='%s already synchronized'\n" "$label"
else
  printf "changed=yes comment='%s synchronization updated files'\n" "$label"
fi
