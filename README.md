# Omarchy Backup Manager 󰁯

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Arch Linux / Omarchy](https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Omarchy-1793D1.svg)](https://omarchy.org/)

A lightweight, low-profile [Omarchy](https://omarchy.org/) status bar plugin and management suite for automated dotfiles backup, 1-click system restore, git synchronization, and system configuration snapshots.

---

## ✨ Features

- **Low-Profile Navbar Widget**:
  - Displays a clean, non-intrusive icon (`󰁯`) directly in the Omarchy top bar.
  - Subtle status indication: idle/up-to-date, syncing animation (`󱑎`), or attention required.
  - Detailed tooltip displaying last backup time, latest commit hash, schedule, and destination.
- **Interactive Management Panel**:
  - **1-Click "Backup Now"**: Immediate backup and push with live progress animation.
  - **1-Click "Restore"**: One-button system restore applying dotfiles configurations and updating local configs, theme, and Hyprland without breaking development links. Cryptographically bound to an explicit commit SHA with confirmation prompt for safety.
  - **Schedule Settings**: Change automated backup interval anytime via dropdown (`Every 1 hour`, `2 hours`, `4 hours`, `6 hours`, `12 hours`, `Daily`, or `Disabled`). Dynamically reconfigures systemd user timers.
  - **Target Git Destination**: View and update the GitHub / Git remote target URL and branch directly in the GUI.
  - **Recent Commit History**: Inspect recent backup commits with relative timestamps.
  - **Integrated Log Viewer**: View real-time backup systemd service logs.
- **Ultra-Low CPU & RAM Footprint**:
  - Zero background daemon loops.
  - Efficient 60-second idle polling (only fast-polls during active syncs/restores).
  - Average CPU utilization: `0.00%`.
  - Native QML declarative bindings with zero memory leaks.

---

## 📦 Dependencies

- **Python 3** (>= 3.8, included by default in Omarchy / Arch Linux)
- **Git** (for version tracking, commit history, and remote GitHub synchronization)
- **systemd** (user services & timers: `omarchy-dotfiles-backup.{timer,service}`)
- **Omarchy Shell / Quickshell** (status bar widget host)

---

## 🚀 Installation

### Via Omarchy Plugin Manager (Recommended):
```bash
omarchy plugin add https://github.com/unrealandychan/omarchy-backup-manager.git --enable
```

### Manual Installation via Git:
```bash
git clone https://github.com/unrealandychan/omarchy-backup-manager.git ~/.local/share/omarchy/plugins/omarchy-backup-manager
cd ~/.local/share/omarchy/plugins/omarchy-backup-manager
./install.sh
```

Or from any local directory:
```bash
./install.sh
```

This will:
1. Symlink `bin/omarchy-backup-ctl` to `~/.local/bin/omarchy-backup-ctl`.
2. Link the plugin to `~/.config/omarchy/plugins/arch.backup-manager`.
3. Register the widget in `~/.config/omarchy/shell.json` on the navigation bar.
4. Notify Omarchy Shell to reload plugins automatically.

---

## 🛠️ CLI Usage (`omarchy-backup-ctl`)

The plugin is backed by the standalone `omarchy-backup-ctl` CLI:

```bash
# Check status and backup metadata (JSON)
omarchy-backup-ctl status

# Trigger an immediate manual backup
omarchy-backup-ctl backup-now
# Or wait for completion:
omarchy-backup-ctl backup-now --wait

# Restore dotfiles bound to an exact, cryptographically verified commit
omarchy-backup-ctl restore --commit <COMMIT_HASH>
# Or restore confirmed local HEAD:
omarchy-backup-ctl restore --head
# (Specifying the target commit binds the restore decision to that exact, cryptographically verified commit, verifying working tree cleanliness and matching committed blob before execution)

# Change automated backup schedule
omarchy-backup-ctl set-frequency 4h     # 1h, 2h, 4h, 6h, 12h, daily, disabled

# Update GitHub / Git destination
omarchy-backup-ctl set-remote "https://github.com/user/my-dotfiles.git"
omarchy-backup-ctl set-branch "main"

# View recent backup logs
omarchy-backup-ctl logs 25
```

---

## 🧪 Testing

A test suite is included in `tests/test-ctl.sh`:

```bash
cd ~/projects/omarchy-backup-manager
./tests/test-ctl.sh
```

---

## 🗑️ Uninstallation

To remove the widget and unlink the plugin:

```bash
cd ~/projects/omarchy-backup-manager
./uninstall.sh
```
