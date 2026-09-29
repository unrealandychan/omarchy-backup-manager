#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CANONICAL_SRC="$(realpath "$SCRIPT_DIR" 2>/dev/null || (cd "$SCRIPT_DIR" && pwd -P))"
BIN_SRC="$SCRIPT_DIR/bin/omarchy-backup-ctl"
CANONICAL_BIN_SRC="$(realpath "$BIN_SRC" 2>/dev/null || true)"
BIN_DEST="$HOME/.local/bin/omarchy-backup-ctl"
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

echo "==> Uninstalling Omarchy Backup Manager Plugin..."

# 1. Safely remove CLI link only if it belongs to this installation
check_ownership "$BIN_DEST"
if [ -L "$BIN_DEST" ]; then
  DEST_REAL="$(realpath "$BIN_DEST" 2>/dev/null || true)"
  DEST_TARGET="$(readlink "$BIN_DEST" 2>/dev/null || true)"
  if [ "$DEST_REAL" = "$CANONICAL_BIN_SRC" ] || [ "$DEST_REAL" = "$BIN_SRC" ] || \
     [ "$DEST_TARGET" = "$CANONICAL_BIN_SRC" ] || [ "$DEST_TARGET" = "$BIN_SRC" ]; then
    rm -f "$BIN_DEST"
    echo "✓ Removed CLI link at $BIN_DEST"
  else
    echo "==> CLI link at $BIN_DEST points to $DEST_TARGET (not this checkout $BIN_SRC); leaving intact."
  fi
elif [ -e "$BIN_DEST" ]; then
  if cmp -s "$BIN_SRC" "$BIN_DEST"; then
    rm -f "$BIN_DEST"
    echo "✓ Removed CLI tool at $BIN_DEST"
  else
    echo "==> File at $BIN_DEST was not installed by this checkout; leaving intact."
  fi
fi

# 2. Safely remove Quickshell plugin link
check_ownership "$PLUGIN_DEST"
if [ -L "$PLUGIN_DEST" ]; then
  CANONICAL_DEST="$(realpath "$PLUGIN_DEST" 2>/dev/null || true)"
  DEST_TARGET="$(readlink "$PLUGIN_DEST" 2>/dev/null || true)"
  DEST_TARGET_CANONICAL="$(realpath -m "$PLUGIN_DEST" 2>/dev/null || true)"
  if [ "$CANONICAL_DEST" = "$SCRIPT_DIR" ] || [ "$CANONICAL_DEST" = "$CANONICAL_SRC" ] || \
     [ "$DEST_TARGET" = "$SCRIPT_DIR" ] || [ "$DEST_TARGET" = "$CANONICAL_SRC" ] || \
     [ "$DEST_TARGET_CANONICAL" = "$SCRIPT_DIR" ] || [ "$DEST_TARGET_CANONICAL" = "$CANONICAL_SRC" ]; then
    rm -f "$PLUGIN_DEST"
    echo "✓ Removed plugin symlink at $PLUGIN_DEST"
  else
    echo "==> Plugin symlink at $PLUGIN_DEST points to $DEST_TARGET (not this checkout $SCRIPT_DIR); leaving intact."
  fi
elif [ -d "$PLUGIN_DEST" ]; then
  CANONICAL_DEST="$(cd "$PLUGIN_DEST" && pwd -P)"
  if [ "$CANONICAL_DEST" = "$SCRIPT_DIR" ] || [ "$CANONICAL_DEST" = "$CANONICAL_SRC" ]; then
    echo "==> Current working directory is $PLUGIN_DEST; keeping checkout intact."
  else
    echo "==> Destination is a standalone directory; keeping $PLUGIN_DEST intact."
  fi
fi

# 3. Safely update shell.json
if [ -e "$SHELL_CONFIG" ] || [ -L "$SHELL_CONFIG" ]; then
  check_ownership "$SHELL_CONFIG"
  if [ -L "$SHELL_CONFIG" ]; then
    echo "Error: $SHELL_CONFIG is a symlink. Refusing to modify." >&2
    exit 1
  fi
  if grep -q "arch.backup-manager" "$SHELL_CONFIG"; then
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

for section in ('left', 'center', 'right'):
    widgets = cfg.get('bar', {}).get('layout', {}).get(section, [])
    cfg['bar']['layout'][section] = [w for w in widgets if w.get('id') != 'arch.backup-manager']

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
    echo "✓ Removed arch.backup-manager from shell.json"
  fi
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins 2>/dev/null || true
fi

echo "✓ Uninstalled Omarchy Backup Manager."
