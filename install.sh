#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CANONICAL_SRC="$(realpath "$SCRIPT_DIR" 2>/dev/null || (cd "$SCRIPT_DIR" && pwd -P))"
BIN_SRC="$SCRIPT_DIR/bin/omarchy-backup-ctl"
CANONICAL_BIN_SRC="$(realpath "$BIN_SRC" 2>/dev/null || true)"
BIN_DEST="$HOME/.local/bin/omarchy-backup-ctl"
PLUGIN_SRC="$SCRIPT_DIR"
PLUGIN_DEST="$HOME/.config/omarchy/plugins/arch.backup-manager"
SHELL_CONFIG="$HOME/.config/omarchy/shell.json"
CURRENT_UID="$(id -u)"

check_ownership() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    local target_uid
    target_uid="$(stat -c %u "$target" 2>/dev/null || true)"
    if [ -n "$target_uid" ] && [ "$target_uid" -ne "$CURRENT_UID" ]; then
      echo "Error: $target is owned by UID $target_uid, not current user UID $CURRENT_UID. Refusing to modify." >&2
      exit 1
    fi
  fi
}

get_unused_backup_path() {
  local target="$1"
  local base="${target}.bak.$(date +%s)"
  local backup="$base"
  local n=1
  while [ -e "$backup" ] || [ -L "$backup" ]; do
    backup="${base}-${n}"
    n=$((n + 1))
  done
  echo "$backup"
}

echo "==> Setting up Omarchy Backup Manager Plugin..."

# 1. Install CLI helper to ~/.local/bin
mkdir -p "$HOME/.local/bin"
chmod +x "$BIN_SRC"
check_ownership "$BIN_DEST"

if [ -L "$BIN_DEST" ]; then
  DEST_REAL="$(realpath "$BIN_DEST" 2>/dev/null || true)"
  DEST_TARGET="$(readlink "$BIN_DEST" 2>/dev/null || true)"
  if [ "$DEST_REAL" = "$CANONICAL_BIN_SRC" ] || [ "$DEST_REAL" = "$BIN_SRC" ] || \
     [ "$DEST_TARGET" = "$CANONICAL_BIN_SRC" ] || [ "$DEST_TARGET" = "$BIN_SRC" ]; then
    echo "✓ CLI tool at $BIN_DEST already points to $BIN_SRC"
  else
    BACKUP="$(get_unused_backup_path "$BIN_DEST")"
    echo "==> Preserving existing CLI symlink: moving $BIN_DEST to $BACKUP..."
    mv "$BIN_DEST" "$BACKUP"
    ln -sfn "$BIN_SRC" "$BIN_DEST"
    echo "✓ Symlinked CLI tool to $BIN_DEST"
  fi
elif [ -e "$BIN_DEST" ]; then
  if cmp -s "$BIN_SRC" "$BIN_DEST"; then
    echo "✓ CLI tool at $BIN_DEST is already identical to source"
  else
    BACKUP="$(get_unused_backup_path "$BIN_DEST")"
    echo "==> Preserving existing CLI file: moving $BIN_DEST to $BACKUP..."
    mv "$BIN_DEST" "$BACKUP"
    ln -sfn "$BIN_SRC" "$BIN_DEST"
    echo "✓ Symlinked CLI tool to $BIN_DEST"
  fi
else
  ln -sfn "$BIN_SRC" "$BIN_DEST"
  echo "✓ Symlinked CLI tool to $BIN_DEST"
fi

# 2. Safely link plugin to Omarchy plugins directory
mkdir -p "$(dirname "$PLUGIN_DEST")"
check_ownership "$PLUGIN_DEST"

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
    BACKUP="$(get_unused_backup_path "$PLUGIN_DEST")"
    echo "==> Preserving existing plugin checkout: moving $PLUGIN_DEST to $BACKUP..."
    mv "$PLUGIN_DEST" "$BACKUP"
    ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
  fi
elif [ -e "$PLUGIN_DEST" ]; then
  BACKUP="$(get_unused_backup_path "$PLUGIN_DEST")"
  echo "==> Preserving existing file at $PLUGIN_DEST: moving to $BACKUP..."
  mv "$PLUGIN_DEST" "$BACKUP"
  ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
else
  echo "✓ Linking plugin to $PLUGIN_DEST..."
  ln -sfn "$PLUGIN_SRC" "$PLUGIN_DEST"
fi

# 3. Add to shell.json if not present
if [ -e "$SHELL_CONFIG" ] || [ -L "$SHELL_CONFIG" ]; then
  check_ownership "$SHELL_CONFIG"
  if [ -L "$SHELL_CONFIG" ]; then
    echo "Error: $SHELL_CONFIG is a symlink. Refusing to modify." >&2
    exit 1
  fi
  if grep -q "arch.backup-manager" "$SHELL_CONFIG"; then
    echo "✓ arch.backup-manager is already present in shell.json"
  else
    echo "==> Adding arch.backup-manager to $SHELL_CONFIG (right bar section)..."
    BACKUP="$(get_unused_backup_path "$SHELL_CONFIG")"
    echo "==> Backing up $SHELL_CONFIG to $BACKUP..."
    cp "$SHELL_CONFIG" "$BACKUP"
    SHELL_CONFIG="$SHELL_CONFIG" python3 -c "
import json, os, tempfile

config_path = os.environ['SHELL_CONFIG']
dirname = os.path.dirname(config_path)
if os.path.islink(config_path):
    raise RuntimeError('Refusing to modify symlinked shell.json')

fd = os.open(config_path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
with os.fdopen(fd, 'r') as f:
    cfg = json.load(f)

right = cfg.get('bar', {}).get('layout', {}).get('right', [])
idx = 1
for i, w in enumerate(right):
    if w.get('id') in ('arch.sysmon', 'omarchy.power'):
        idx = i
        break
right.insert(idx, {'id': 'arch.backup-manager'})

temp_path = None
try:
    with tempfile.NamedTemporaryFile('w', dir=dirname, delete=False) as tf:
        temp_path = tf.name
        json.dump(cfg, tf, indent=2)
        tf.flush()
        os.fsync(tf.fileno())
    os.chmod(temp_path, 0o644)
    os.replace(temp_path, config_path)
    temp_path = None
finally:
    if temp_path and os.path.exists(temp_path):
        try:
            os.unlink(temp_path)
        except OSError:
            pass
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
