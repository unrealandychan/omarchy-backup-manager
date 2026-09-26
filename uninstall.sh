#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DEST="$HOME/.local/bin/omarchy-backup-ctl"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/arch.backup-manager"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"

echo "==> Uninstalling Omarchy Backup Manager Plugin..."

rm -f "$BIN_DEST"
echo "✓ Removed CLI link at $BIN_DEST"

if [ -L "$PLUGIN_DEST" ]; then
  rm -f "$PLUGIN_DEST"
  echo "✓ Removed plugin symlink at $PLUGIN_DEST"
elif [ -d "$PLUGIN_DEST" ]; then
  CANONICAL_DEST="$(cd "$PLUGIN_DEST" && pwd -P)"
  if [ "$CANONICAL_DEST" = "$SCRIPT_DIR" ]; then
    echo "==> Current working directory is $PLUGIN_DEST; keeping checkout intact."
  else
    echo "==> Destination is a standalone directory; keeping $PLUGIN_DEST intact."
  fi
fi

if [ -f "$SHELL_CONFIG" ]; then
  python3 -c "
import json
with open('$SHELL_CONFIG', 'r') as f:
    cfg = json.load(f)
for section in ('left', 'center', 'right'):
    widgets = cfg.get('bar', {}).get('layout', {}).get(section, [])
    cfg['bar']['layout'][section] = [w for w in widgets if w.get('id') != 'arch.backup-manager']
with open('$SHELL_CONFIG', 'w') as f:
    json.dump(cfg, f, indent=2)
"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins 2>/dev/null || true
fi

echo "✓ Uninstalled Omarchy Backup Manager."
