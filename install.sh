#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_SRC="$SCRIPT_DIR/bin/omarchy-backup-ctl"
BIN_DEST="$HOME/.local/bin/omarchy-backup-ctl"
PLUGIN_SRC="$SCRIPT_DIR"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/arch.backup-manager"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"

echo "==> Setting up Omarchy Backup Manager Plugin..."

# 1. Install CLI helper to ~/.local/bin
mkdir -p "$HOME/.local/bin"
chmod +x "$BIN_SRC"
ln -nsf "$BIN_SRC" "$BIN_DEST"
echo "✓ Symlinked CLI tool to $BIN_DEST"

# 2. Link plugin to Omarchy plugins directory
mkdir -p "$(dirname "$PLUGIN_DEST")"
rm -rf "$PLUGIN_DEST"
ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
echo "✓ Symlinked plugin to $PLUGIN_DEST"

# 3. Add to shell.json if not present
if [ -f "$SHELL_CONFIG" ]; then
  if grep -q "arch.backup-manager" "$SHELL_CONFIG"; then
    echo "✓ arch.backup-manager is already present in shell.json"
  else
    echo "==> Adding arch.backup-manager to $SHELL_CONFIG (right bar section)..."
    cp "$SHELL_CONFIG" "$SHELL_CONFIG.bak.$(date +%s)"
    python3 -c "
import json
with open('$SHELL_CONFIG', 'r') as f:
    cfg = json.load(f)
right = cfg.get('bar', {}).get('layout', {}).get('right', [])
# Insert before arch.sysmon or at position 2
idx = 1
for i, w in enumerate(right):
    if w.get('id') in ('arch.sysmon', 'omarchy.power'):
        idx = i
        break
right.insert(idx, {'id': 'arch.backup-manager'})
with open('$SHELL_CONFIG', 'w') as f:
    json.dump(cfg, f, indent=2)
"
    echo "✓ Added arch.backup-manager to shell.json"
  fi
fi

# 4. Trigger rescan in Omarchy Shell
echo "==> Notifying Omarchy Shell of new plugin..."
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins 2>/dev/null || true
fi

echo "🎉 Backup Manager plugin installed successfully!"
