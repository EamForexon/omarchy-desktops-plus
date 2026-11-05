import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Workspace numbers for the bar, one copy per monitor. On each monitor:
//   underline  - the workspace has windows on this monitor
//   dot        - the workspace lives on this monitor but is empty
//   glyph      - the workspace is on screen (smaller when it's another monitor's)
BarWidget {
  id: root
  moduleName: "desktops-plus.workspaces"

  // Always listed, even when they don't exist. Keep in sync with
  // keepAlive in Service.qml.
  readonly property int alwaysShown: 5

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = []
    for (var n = 1; n <= root.alwaysShown; n++) ids.push(n)
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  readonly property var ids: workspaceIds()

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Output this bar copy lives on; workspaces with windows on it get a border.
  readonly property string screenName: {
    var win = root.QsWindow.window
    return win && win.screen ? String(win.screen.name || "") : ""
  }

  // Moving a workspace between monitors fires several focus events in a row;
  // settle before swapping the focused glyph so it doesn't jump around.
  property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

  Timer {
    id: focusSettle
    interval: 150
    onTriggered: root.focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { focusSettle.restart() }

    // Hyprland sends no focus event after moving the active workspace to
    // another monitor, so Quickshell keeps the stale one. Re-read the state.
    function onRawEvent(event) {
      if (event.name !== "moveworkspacev2") return
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
      focusSettle.restart()
    }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.ids.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.ids

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: root.focusedId === modelData
        readonly property bool onThisScreen: workspace !== null && workspace.monitor !== null && workspace.monitor.name === root.screenName
        // Shown on the unfocused monitor: same glyph as the focused one, dimmed.
        readonly property bool visibleElsewhere: !focused && workspace !== null && workspace.monitor !== null
          && workspace.monitor.activeWorkspace !== null && workspace.monitor.activeWorkspace.id === modelData

        bar: root.bar
        text: focused || visibleElsewhere ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: focused || (occupied && !visibleElsewhere) ? 1 : 0.5
        // Smaller glyph when that workspace is showing on another monitor.
        fontSize: (focused || visibleElsewhere) && !onThisScreen ? Math.round(Style.font.body * 0.75) : Style.font.body
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        // Underline: this workspace has windows on this bar's monitor.
        Rectangle {
          id: underline
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(1)
          width: Style.space(8)
          height: 2
          radius: 1
          color: root.bar ? root.bar.barForeground : Color.foreground
          visible: parent.onThisScreen && parent.occupied
        }

        // Dot: this workspace lives on this bar's monitor but has no windows.
        // Dimmed like an inactive number, even when the button itself isn't.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: underline.verticalCenter
          width: 2
          height: 2
          color: root.bar ? root.bar.barForeground : Color.foreground
          opacity: parent.opacity < 1 ? 1 : 0.5
          visible: parent.onThisScreen && !parent.occupied
        }
      }
    }
  }
}
