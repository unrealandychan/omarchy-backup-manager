# Omarchy Backup Manager 󰁯

A lightweight, low-profile [Omarchy](https://omarchy.org/) status bar plugin and management suite for automated dotfiles backup, git synchronization, and system configuration snapshots.

---

## ✨ Features

- **Low-Profile Navbar Widget**:
  - Displays a clean, non-intrusive icon (`󰁯`) directly in the Omarchy top bar.
  - Subtle status indication: idle/up-to-date, syncing animation (`󱑎`), or attention required.
  - Detailed tooltip displaying last backup time, latest commit hash, schedule, and destination.
- **Interactive Management Panel**:
  - One-click **"Backup Now"** button with live progress indicator.
  - **Schedule Settings**: Change automated backup interval anytime via dropdown (`Every 1 hour`, `2 hours`, `4 hours`, `6 hours`, `12 hours`, `Daily`, or `Disabled`). Dynamically reconfigures systemd user timers.
  - **Target Git Destination**: View and update the GitHub / Git remote target URL and branch directly in the GUI.
  - **Recent Commit History**: Inspect recent backup commits with relative timestamps.
  - **Integrated Log Viewer**: View real-time backup systemd service logs.
- **Ultra-Low CPU & RAM Footprint**:
  - Zero background daemon loops.
  - Efficient 60-second idle polling (only fast-polls during active syncs).
  - Average CPU utilization: `0.00%`.
  - Native QML declarative bindings with zero memory leaks.

---

## 🚀 Installation

Run the installation script inside this repository:

```bash
cd ~/projects/omarchy-backup-manager
./install.sh
```

This will:
1. Symlink `bin/omarchy-backup-ctl` to `~/.local/bin/omarchy-backup-ctl`.
2. Link the plugin to `~/.config/omarchy/plugins/arch.backup-manager`.
3. Register the widget in `~/.config/omarchy/shell.json` on the right side of the navigation bar.
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
