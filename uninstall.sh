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
THIS_INSTALLATION_OWNS_PLUGIN=0

if [ -L "$PLUGIN_DEST" ]; then
  CANONICAL_DEST="$(realpath "$PLUGIN_DEST" 2>/dev/null || true)"
  DEST_TARGET="$(readlink "$PLUGIN_DEST" 2>/dev/null || true)"
  DEST_TARGET_CANONICAL="$(realpath -m "$PLUGIN_DEST" 2>/dev/null || true)"
  if [ "$CANONICAL_DEST" = "$SCRIPT_DIR" ] || [ "$CANONICAL_DEST" = "$CANONICAL_SRC" ] || \
     [ "$DEST_TARGET" = "$SCRIPT_DIR" ] || [ "$DEST_TARGET" = "$CANONICAL_SRC" ] || \
     [ "$DEST_TARGET_CANONICAL" = "$SCRIPT_DIR" ] || [ "$DEST_TARGET_CANONICAL" = "$CANONICAL_SRC" ]; then
    rm -f "$PLUGIN_DEST"
    echo "✓ Removed plugin symlink at $PLUGIN_DEST"
    THIS_INSTALLATION_OWNS_PLUGIN=1
  else
    echo "==> Plugin symlink at $PLUGIN_DEST points to $DEST_TARGET (not this checkout $SCRIPT_DIR); leaving intact."
  fi
elif [ -d "$PLUGIN_DEST" ]; then
  CANONICAL_DEST="$(cd "$PLUGIN_DEST" && pwd -P)"
  if [ "$CANONICAL_DEST" = "$SCRIPT_DIR" ] || [ "$CANONICAL_DEST" = "$CANONICAL_SRC" ]; then
    echo "==> Current working directory is $PLUGIN_DEST; keeping checkout intact."
    THIS_INSTALLATION_OWNS_PLUGIN=1
  else
    echo "==> Destination is a standalone directory; keeping $PLUGIN_DEST intact."
  fi
else
  THIS_INSTALLATION_OWNS_PLUGIN=1
fi

# 3. Safely update shell.json
if [ "$THIS_INSTALLATION_OWNS_PLUGIN" -eq 1 ]; then
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
import json, os, tempfile, sys

config_path = os.environ['SHELL_CONFIG']
dirname = os.path.dirname(config_path)
basename = os.path.basename(config_path)
current_uid = os.getuid()

dir_fd = os.open(dirname, os.O_RDONLY | os.O_DIRECTORY | getattr(os, 'O_NOFOLLOW', 0))
try:
    dir_stat = os.fstat(dir_fd)
    if dir_stat.st_uid != current_uid:
        raise PermissionError(f'Directory {dirname} is owned by UID {dir_stat.st_uid}, not {current_uid}')

    fd = os.open(basename, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0), dir_fd=dir_fd)
    try:
        st = os.fstat(fd)
        if st.st_uid != current_uid:
            raise PermissionError(f'File {basename} is owned by UID {st.st_uid}, not {current_uid}')
        orig_mode = st.st_mode & 0o777
        with os.fdopen(fd, 'r', encoding='utf-8') as f:
            cfg = json.load(f)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        raise

    for section in ('left', 'center', 'right'):
        widgets = cfg.get('bar', {}).get('layout', {}).get(section, [])
        cfg['bar']['layout'][section] = [w for w in widgets if w.get('id') != 'arch.backup-manager']

    tmp_fd, tmp_path = tempfile.mkstemp(prefix=f'.{basename}-', suffix='.tmp', dir=dirname)
    tmp_base = os.path.basename(tmp_path)
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
            json.dump(cfg, f, indent=2)
            f.write('\n')
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp_path, orig_mode)
        os.replace(tmp_base, basename, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        tmp_path = None
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
finally:
    os.close(dir_fd)
"
    echo "✓ Removed arch.backup-manager from shell.json"
  fi
fi

  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins 2>/dev/null || true
  fi
else
  echo "==> Active plugin at $PLUGIN_DEST is not owned by this checkout; leaving shell.json intact."
fi

echo "✓ Uninstalled Omarchy Backup Manager."
