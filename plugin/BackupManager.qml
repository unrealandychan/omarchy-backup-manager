import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "arch.backup-manager"

  // Settings from shell.json
  property bool showLabel: setting("showLabel", false)
  property bool showRelativeTime: setting("showRelativeTime", false)

  // Status state
  property string statusState: "idle" // "idle", "syncing", "error"
  property string lastBackupTime: "Checking..."
  property string lastBackupRelative: "..."
  property string lastCommitHash: ""
  property string lastCommitSubject: ""
  property bool timerActive: true
  property string frequency: "4h"
  property string frequencyLabel: "Every 4 hours"
  property string nextTrigger: ""
  property string remoteUrl: ""
  property string remoteDisplay: ""
  property string branch: "main"
  property int uncommittedChanges: 0
  property int unpushedCommits: 0
  property var historyList: []
  property string recentLogs: ""
  property bool showLogsPanel: false
  property string notificationMessage: ""

  // UI state
  property bool popupOpen: false
  readonly property bool isSyncing: statusState === "syncing"
  property bool isRestoring: false
  property bool confirmRestoreOpen: false

  // Script path: dynamically resolved relative to plugin location with fallback
  readonly property string ctlPath: {
    var resolved = Qt.resolvedUrl("../bin/omarchy-backup-ctl")
    var localPath = decodeURIComponent(String(resolved).replace(/^file:\/\//, ""))
    return localPath
  }

  // Omarchy Shell panel contract: opened, open(), close(), toggle()
  readonly property bool opened: popupOpen
  function open() { root.openPopup() }
  function close() { root.closePopup() }
  function toggle() { root.togglePopup() }

  function openPopup() {
    root.popupOpen = true
    root.refreshStatus()
  }

  function closePopup() {
    root.popupOpen = false
    root.showLogsPanel = false
  }

  function togglePopup() {
    if (root.popupOpen) {
      root.closePopup()
    } else {
      root.openPopup()
    }
  }

  onPopupOpenChanged: {
    if (popup && popup.open !== root.popupOpen) {
      popup.open = root.popupOpen
    }
  }

  // Refresh status from CLI
  function refreshStatus() {
    if (!statusProc.running) {
      statusProc.running = true
    }
  }

  // Trigger manual backup
  function triggerBackup() {
    root.confirmRestoreOpen = false
    root.statusState = "syncing"
    root.notificationMessage = "Backup initiated…"
    if (!backupProc.running) {
      backupProc.running = true
    }
  }

  // Trigger 1-button restore
  function triggerRestore() {
    root.confirmRestoreOpen = false
    root.isRestoring = true
    root.notificationMessage = "Restoring dotfiles from repository…"
    if (root.lastCommitHash) {
      restoreProc.command = [root.ctlPath, "restore", "--confirm-commit", root.lastCommitHash]
    } else {
      restoreProc.command = [root.ctlPath, "restore", "--no-pull"]
    }
    if (!restoreProc.running) {
      restoreProc.running = true
    }
  }

  // Change frequency
  function updateFrequency(newFreq) {
    if (newFreq === root.frequency) return
    freqProc.command = [root.ctlPath, "set-frequency", newFreq]
    freqProc.running = true
  }

  // Change remote URL
  function updateRemote(newUrl) {
    if (!newUrl || newUrl.trim() === "" || newUrl === root.remoteUrl) return
    remoteProc.command = [root.ctlPath, "set-remote", newUrl.trim()]
    remoteProc.running = true
  }

  // Change branch
  function updateBranch(newBranch) {
    if (!newBranch || newBranch.trim() === "" || newBranch === root.branch) return
    branchProc.command = [root.ctlPath, "set-branch", newBranch.trim()]
    branchProc.running = true
  }

  // Load logs
  function fetchLogs() {
    if (!logsProc.running) {
      logsProc.running = true
    }
  }

  // Open repository in browser
  function openRepository() {
    if (root.remoteUrl) {
      var url = root.remoteUrl
      if (url.indexOf("git@github.com:") === 0) {
        url = url.replace("git@github.com:", "https://github.com/")
      }
      url = url.replace(/\.git$/, "")
      var urlPattern = /^https?:\/\/[a-zA-Z0-9\-._~:\/?#\[\]@!$&'()*+,;%=]+$/
      if (urlPattern.test(url)) {
        Quickshell.execDetached(["xdg-open", url])
      } else {
        console.warn("[BackupManager] Refusing to open invalid or untrusted URL: " + url)
      }
    }
  }

  // Low-profile display text and styling
  readonly property string displayIcon: (isSyncing || isRestoring) ? "󱑎" : "󰁯"

  readonly property string displayText: {
    if (root.vertical) return root.displayIcon
    if (isSyncing) return root.displayIcon + " Syncing…"
    if (isRestoring) return root.displayIcon + " Restoring…"
    if (root.showRelativeTime && root.lastBackupRelative !== "Never" && root.lastBackupRelative !== "...") {
      return root.displayIcon + " " + root.lastBackupRelative
    }
    if (root.uncommittedChanges > 0) {
      return root.displayIcon + " *"
    }
    return root.displayIcon
  }

  readonly property color widgetColor: {
    if (isSyncing || isRestoring) return Color.accent
    if (root.uncommittedChanges > 0 || root.unpushedCommits > 0) return "#f9e2af"
    return Color.foreground
  }

  readonly property string tooltipDetails: {
    var t = "󰁯 Dotfiles Backup Manager\n"
    t += "───────────────────────────\n"
    if (isSyncing) {
      t += "Status: Backup in progress…\n"
    } else if (isRestoring) {
      t += "Status: Restoring dotfiles…\n"
    } else {
      t += "Status: " + (root.uncommittedChanges > 0 ? "Changes pending" : "Up to date") + "\n"
    }
    t += "Last Backup: " + root.lastBackupTime + " (" + root.lastBackupRelative + ")\n"
    if (root.lastCommitHash) {
      t += "Commit: " + root.lastCommitHash + " — " + root.lastCommitSubject + "\n"
    }
    t += "Schedule: " + root.frequencyLabel + "\n"
    if (root.nextTrigger) {
      t += "Next Run: " + root.nextTrigger + "\n"
    }
    if (root.remoteDisplay) {
      t += "Destination: " + root.remoteDisplay + " (" + root.branch + ")\n"
    }
    t += "───────────────────────────\n"
    t += "Click to open Backup Manager & Settings"
    return t
  }

  // Background polling timer: 60s when idle, 2.5s when syncing or restoring (ultra-low CPU)
  Timer {
    id: pollTimer
    interval: (root.isSyncing || root.isRestoring) ? 2500 : 60000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  // Auto-dismiss transient notification message after 4s
  Timer {
    id: notifyTimer
    interval: 4000
    repeat: false
    running: root.notificationMessage !== ""
    onTriggered: root.notificationMessage = ""
  }

  // Process 1: Status reader
  Process {
    id: statusProc
    command: [root.ctlPath, "status"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text.trim())
          if (!data) return
          root.statusState = data.status || "idle"
          root.lastBackupTime = data.last_backup_time || "Never"
          root.lastBackupRelative = data.last_backup_relative || "Never"
          root.lastCommitHash = data.last_commit_hash || ""
          root.lastCommitSubject = data.last_commit_subject || ""
          root.timerActive = data.timer_active === true
          root.frequency = data.frequency || "4h"
          root.frequencyLabel = data.frequency_label || "Every 4 hours"
          root.nextTrigger = data.next_trigger || ""
          root.remoteUrl = data.remote_url || ""
          root.remoteDisplay = data.remote_display || ""
          root.branch = data.branch || "main"
          root.uncommittedChanges = data.uncommitted_changes || 0
          root.unpushedCommits = data.unpushed_commits || 0
          root.historyList = data.history || []
        } catch(e) {
          // ignore parsing error
        }
      }
    }
  }

  // Process 2: Backup Now action
  Process {
    id: backupProc
    command: [root.ctlPath, "backup-now"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text.trim())
          root.notificationMessage = res.message || "Backup completed."
        } catch(e) {
          root.notificationMessage = "Backup task started."
        }
        root.refreshStatus()
      }
    }
  }

  // Process 3: Set Frequency
  Process {
    id: freqProc
    command: [root.ctlPath, "set-frequency", "4h"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text.trim())
          root.notificationMessage = res.message || "Schedule updated."
        } catch(e) {
          root.notificationMessage = "Schedule updated."
        }
        root.refreshStatus()
      }
    }
  }

  // Process 4: Set Remote URL
  Process {
    id: remoteProc
    command: [root.ctlPath, "set-remote", ""]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text.trim())
          root.notificationMessage = res.message || "Remote updated."
        } catch(e) {
          root.notificationMessage = "Remote updated."
        }
        root.refreshStatus()
      }
    }
  }

  // Process 5: Set Branch
  Process {
    id: branchProc
    command: [root.ctlPath, "set-branch", ""]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text.trim())
          root.notificationMessage = res.message || "Branch updated."
        } catch(e) {
          root.notificationMessage = "Branch updated."
        }
        root.refreshStatus()
      }
    }
  }

  // Process 6: Logs Reader
  Process {
    id: logsProc
    command: [root.ctlPath, "logs", "30"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text.trim())
          root.recentLogs = res.logs || "No logs available."
        } catch(e) {
          root.recentLogs = "Error loading logs."
        }
      }
    }
  }

  // Process 7: 1-Button Restore action
  Process {
    id: restoreProc
    command: [root.ctlPath, "restore"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isRestoring = false
        root.confirmRestoreOpen = false
        try {
          var res = JSON.parse(text.trim())
          root.notificationMessage = res.message || (res.success ? "Dotfiles restored successfully." : ("Restore failed: " + res.error))
        } catch(e) {
          root.notificationMessage = "Restore completed."
        }
        root.refreshStatus()
      }
    }
  }

  // Layout sizing
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Low-profile Navbar Button
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.tooltipDetails
    active: root.isSyncing || root.uncommittedChanges > 0
    activeColor: root.widgetColor
    onPressed: function(btn) {
      root.togglePopup()
    }
  }

  // Popup Management Panel
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    onOpenChanged: {
      if (open !== root.popupOpen) {
        root.popupOpen = open
      }
    }
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(panelContent.implicitHeight)

    FocusScope {
      id: focusScope
      anchors.fill: parent
      implicitHeight: panelContent.implicitHeight
      implicitWidth: panelContent.implicitWidth
      focus: root.popupOpen
      Keys.onEscapePressed: function(event) {
        root.closePopup()
        event.accepted = true
      }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_R) {
          root.refreshStatus()
          event.accepted = true
        }
      }

      ColumnLayout {
        id: panelContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ──────────────── Header ────────────────
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "󰁯"
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            color: Color.accent
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            text: "Dotfiles Backup Manager"
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            color: Color.foreground
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
          }

          // Status Badge Pill
          Rectangle {
            implicitHeight: Style.space(22)
            implicitWidth: statusBadgeText.implicitWidth + Style.space(16)
            radius: Style.space(11)
            Layout.alignment: Qt.AlignVCenter
            color: root.isSyncing
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
              : (root.uncommittedChanges > 0
                  ? Qt.rgba(0.97, 0.88, 0.68, 0.2)
                  : Qt.rgba(0.65, 0.89, 0.63, 0.2))
            border.width: 1
            border.color: root.isSyncing
              ? Color.accent
              : (root.uncommittedChanges > 0 ? "#f9e2af" : "#a6e3a1")

            Text {
              id: statusBadgeText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: root.isSyncing
                ? "󱑎 Syncing…"
                : (root.uncommittedChanges > 0 ? "● Pending changes" : "● Up to date")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.isSyncing
                ? Color.accent
                : (root.uncommittedChanges > 0 ? "#f9e2af" : "#a6e3a1")
            }
          }

          // Refresh Button
          Button {
            iconText: ""
            tooltipText: "Refresh status (R)"
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(4)
            Layout.alignment: Qt.AlignVCenter
            onClicked: root.refreshStatus()
          }
        }

        // Transient notification message banner
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: notifyMsg.implicitHeight + Style.space(10)
          visible: root.notificationMessage !== ""
          radius: Style.space(6)
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
          border.width: 1
          border.color: Color.accent

          Text {
            id: notifyMsg
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.notificationMessage
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.accent
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        // ──────────────── Overview Card ────────────────
        BorderSurface {
          id: overviewCard
          Layout.fillWidth: true
          implicitHeight: overviewCol.implicitHeight + topPadding + bottomPadding
          radius: Style.space(6)
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
          border.width: 1
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
          leftPadding: Style.space(12)
          rightPadding: Style.space(12)

          ColumnLayout {
            id: overviewCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: parent.leftPadding
            anchors.rightMargin: parent.rightPadding
            anchors.topMargin: parent.topPadding
            spacing: Style.space(6)

            // Last backup row
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)
              Text {
                text: "Last Backup:"
                font.bold: true
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.preferredWidth: Style.space(90)
                Layout.alignment: Qt.AlignVCenter
              }
              Text {
                text: root.lastBackupTime + (root.lastBackupRelative !== "Never" ? " (" + root.lastBackupRelative + ")" : "")
                textFormat: Text.PlainText
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
              }
            }

            // Last commit row
            RowLayout {
              visible: root.lastCommitHash !== ""
              Layout.fillWidth: true
              spacing: Style.space(8)
              Text {
                text: "Latest Commit:"
                font.bold: true
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.preferredWidth: Style.space(90)
                Layout.alignment: Qt.AlignVCenter
              }
              Text {
                text: root.lastCommitHash + " · " + root.lastCommitSubject
                textFormat: Text.PlainText
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
              }
            }

            // Schedule row
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)
              Text {
                text: "Schedule:"
                font.bold: true
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.preferredWidth: Style.space(90)
                Layout.alignment: Qt.AlignVCenter
              }
              Text {
                text: root.frequencyLabel + (root.nextTrigger ? "  (Next: " + root.nextTrigger + ")" : "")
                textFormat: Text.PlainText
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
              }
            }

            // Destination row
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)
              Text {
                text: "Destination:"
                font.bold: true
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.preferredWidth: Style.space(90)
                Layout.alignment: Qt.AlignVCenter
              }
              Text {
                text: (root.remoteDisplay || root.remoteUrl || "Not configured") + " [" + root.branch + "]"
                textFormat: Text.PlainText
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
              }
            }
          }
        }

        // Primary Action Buttons
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Button {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(32)
            Layout.alignment: Qt.AlignVCenter
            text: root.isSyncing ? "Backing up…" : "Backup Now"
            iconText: root.isSyncing ? "󱑎" : "󰁯"
            bordered: true
            accent: Color.accent
            selected: true
            enabled: !root.isSyncing && !root.isRestoring
            onClicked: root.triggerBackup()
          }

          Button {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(32)
            Layout.alignment: Qt.AlignVCenter
            text: root.isRestoring ? "Restoring…" : "Restore"
            iconText: root.isRestoring ? "󱑎" : "󰁝"
            bordered: true
            accent: "#89b4fa"
            enabled: !root.isSyncing && !root.isRestoring
            onClicked: {
              root.confirmRestoreOpen = !root.confirmRestoreOpen
            }
          }

          Button {
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: Style.space(32)
            Layout.alignment: Qt.AlignVCenter
            text: "GitHub"
            iconText: "󰆏"
            bordered: true
            onClicked: root.openRepository()
          }
        }

        // Restore Confirmation Box (1-Click confirmation for safety)
        Rectangle {
          visible: root.confirmRestoreOpen
          Layout.fillWidth: true
          implicitHeight: restoreConfirmCol.implicitHeight + Style.space(16)
          radius: Style.space(6)
          color: Qt.rgba(0.97, 0.7, 0.2, 0.12)
          border.width: 1
          border.color: Qt.rgba(0.97, 0.7, 0.2, 0.5)

          ColumnLayout {
            id: restoreConfirmCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Text {
              text: "󰳦 Confirm Dotfiles Restore"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              color: "#f9e2af"
            }

            Text {
              text: (root.lastCommitHash ? ("Target commit: " + root.lastCommitHash + (root.lastCommitSubject ? (" — " + root.lastCommitSubject) : "")) : "Applying verified local repository configuration") + "\nExecuting verified ~/dotfiles/install.sh (or restore.sh)"
              textFormat: Text.PlainText
              font.family: Style.font.family
              font.pixelSize: Style.font.caption - 1
              color: Color.muted
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Button {
                text: "Confirm Restore"
                iconText: "󰁝"
                bordered: true
                accent: "#a6e3a1"
                selected: true
                fontSize: Style.font.caption
                onClicked: root.triggerRestore()
              }

              Button {
                text: "Cancel"
                bordered: true
                fontSize: Style.font.caption
                onClicked: {
                  root.confirmRestoreOpen = false
                }
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        // ──────────────── Settings Section ────────────────
        PanelSectionHeader {
          text: "SCHEDULE & DESTINATION SETTINGS"
        }

        // Frequency Dropdown Row
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "Frequency:"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Color.foreground
            Layout.preferredWidth: Style.space(90)
            Layout.alignment: Qt.AlignVCenter
          }

          Dropdown {
            id: freqDropdown
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            showLabel: false
            value: root.frequency
            options: [
              { label: "Every 1 hour", value: "1h" },
              { label: "Every 2 hours", value: "2h" },
              { label: "Every 4 hours (Default)", value: "4h" },
              { label: "Every 6 hours", value: "6h" },
              { label: "Every 12 hours", value: "12h" },
              { label: "Daily (Midnight)", value: "daily" },
              { label: "Manual only (Disabled)", value: "disabled" }
            ]
            onChanged: function(val) {
              root.updateFrequency(val)
            }
          }
        }

        // Remote Destination Input Row
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "Target URL:"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Color.foreground
            Layout.preferredWidth: Style.space(90)
            Layout.alignment: Qt.AlignVCenter
          }

          TextField {
            id: remoteInput
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.remoteUrl
            placeholderText: "https://github.com/user/dotfiles.git"
            onAccepted: root.updateRemote(text)
          }

          Button {
            text: "Save"
            Layout.alignment: Qt.AlignVCenter
            fontSize: Style.font.caption
            bordered: true
            onClicked: root.updateRemote(remoteInput.text)
          }
        }

        // Branch Input Row
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "Git Branch:"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Color.foreground
            Layout.preferredWidth: Style.space(90)
            Layout.alignment: Qt.AlignVCenter
          }

          TextField {
            id: branchInput
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.branch
            placeholderText: "main"
            onAccepted: root.updateBranch(text)
          }

          Button {
            text: "Save"
            Layout.alignment: Qt.AlignVCenter
            fontSize: Style.font.caption
            bordered: true
            onClicked: root.updateBranch(branchInput.text)
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        // ──────────────── Recent Backups History ────────────────
        PanelSectionHeader {
          text: "RECENT BACKUP COMMITS"
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Repeater {
            model: root.historyList
            delegate: Rectangle {
              Layout.fillWidth: true
              implicitHeight: historyCol.implicitHeight + Style.space(12)
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              radius: Style.space(4)
              border.width: 1
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

              ColumnLayout {
                id: historyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(6)
                spacing: Style.space(2)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(6)
                  Text {
                    text: modelData.hash || ""
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: Color.accent
                  }
                  Text {
                    text: "·"
                    color: Color.muted
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    text: modelData.relative || modelData.date || ""
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                  }
                  Item { Layout.fillWidth: true }
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.subject || ""
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.foreground
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          Text {
            visible: root.historyList.length === 0
            text: "No recent backup commits found."
            color: Color.muted
            font.pixelSize: Style.font.caption
            font.italic: true
          }
        }

        // ──────────────── Logs Panel / Toggle ────────────────
        RowLayout {
          Layout.fillWidth: true
          Button {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(28)
            Layout.alignment: Qt.AlignVCenter
            text: root.showLogsPanel ? "Hide Backup Logs" : "View Recent Backup Logs"
            iconText: "󰌒"
            fontSize: Style.font.caption
            bordered: true
            onClicked: {
              root.showLogsPanel = !root.showLogsPanel
              if (root.showLogsPanel) root.fetchLogs()
            }
          }
        }

        ScrollView {
          visible: root.showLogsPanel
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(120)
          clip: true

          TextArea {
            text: root.recentLogs || "Loading logs…"
            textFormat: Text.PlainText
            readOnly: true
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            color: Color.foreground
            wrapMode: Text.WrapAnywhere
            background: Rectangle {
              color: Qt.rgba(0, 0, 0, 0.4)
              radius: Style.space(4)
              border.width: 1
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
            }
          }
        }
      }
    }
  }
}
