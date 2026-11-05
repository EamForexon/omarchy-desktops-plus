import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Keeps every workspace on the monitor it was last on, so the bar can show it
// there and SUPER+number goes back to that monitor. Workspaces 1..keepAlive
// stay alive when empty; the rest close like stock Omarchy.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  // Keep in sync with alwaysShown in Workspaces.qml.
  readonly property int keepAlive: 5

  readonly property string script: String(Qt.resolvedUrl("bin/sync.sh")).replace(/^file:\/\//, "")
  readonly property var triggers: ["createworkspacev2", "moveworkspacev2", "configreloaded", "monitoraddedv2", "monitorremovedv2"]

  // A monitor came back: move its workspaces home on the next sync.
  property bool restorePending: true

  Process {
    id: sync
    command: [root.script, String(root.keepAlive), root.restorePending ? "restore" : ""]
    onStarted: root.restorePending = false
  }

  // Events come in bursts (moving a workspace fires several); sync once after.
  Timer {
    id: settle
    interval: 300
    onTriggered: {
      if (sync.running) settle.restart()
      else sync.running = true
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.triggers.indexOf(event.name) === -1) return
      if (event.name === "monitoraddedv2") root.restorePending = true
      settle.restart()
    }
  }

  Component.onCompleted: settle.restart()
}
