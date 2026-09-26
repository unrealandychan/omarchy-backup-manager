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

# 2. Safely link plugin to Omarchy plugins directory
mkdir -p "$(dirname "$PLUGIN_DEST")"

CANONICAL_SRC="$(cd "$PLUGIN_SRC" && pwd -P)"
CURRENT_UID="$(id -u)"

# Verify ownership of destination if it exists or is a symlink
if [ -e "$PLUGIN_DEST" ] || [ -L "$PLUGIN_DEST" ]; then
  DEST_UID="$(stat -c %u "$PLUGIN_DEST" 2>/dev/null || true)"
  if [ -n "$DEST_UID" ] && [ "$DEST_UID" -ne "$CURRENT_UID" ]; then
    echo "Error: $PLUGIN_DEST is owned by UID $DEST_UID, not current user UID $CURRENT_UID. Refusing to modify." >&2
    exit 1
  fi
fi

if [ -L "$PLUGIN_DEST" ]; then
  CANONICAL_DEST="$(realpath "$PLUGIN_DEST" 2>/dev/null || true)"
  if [ "$CANONICAL_DEST" = "$CANONICAL_SRC" ]; then
    echo "✓ Plugin symlink at $PLUGIN_DEST already points to $PLUGIN_SRC"
  else
    echo "✓ Updating plugin symlink at $PLUGIN_DEST..."
    ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
  fi
elif [ -d "$PLUGIN_DEST" ]; then
  CANONICAL_DEST="$(cd "$PLUGIN_DEST" && pwd -P)"
  if [ "$CANONICAL_DEST" = "$CANONICAL_SRC" ]; then
    echo "✓ Running from destination directory ($PLUGIN_DEST); preserving source."
  else
    BACKUP_BASE="${PLUGIN_DEST}.bak.$(date +%s)"
    echo "==> Preserving existing plugin checkout: moving $PLUGIN_DEST to $BACKUP_BASE..."
    mv "$PLUGIN_DEST" "$BACKUP_BASE"
    ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
  fi
elif [ -e "$PLUGIN_DEST" ]; then
  BACKUP_BASE="${PLUGIN_DEST}.bak.$(date +%s)"
  echo "==> Preserving existing file at $PLUGIN_DEST: moving to $BACKUP_BASE..."
  mv "$PLUGIN_DEST" "$BACKUP_BASE"
  ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
else
  echo "✓ Linking plugin to $PLUGIN_DEST..."
  ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
fi

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
