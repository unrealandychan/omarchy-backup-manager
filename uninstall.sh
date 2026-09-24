#!/usr/bin/env bash
set -euo pipefail

BIN_DEST="$HOME/.local/bin/omarchy-backup-ctl"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/arch.backup-manager"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"

echo "==> Uninstalling Omarchy Backup Manager Plugin..."

rm -f "$BIN_DEST"
rm -rf "$PLUGIN_DEST"

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
