import QtQuick
import qs.Ui
import qs.Commons

// Padlock next to the indicators. Toggles `bar.locked`, which the Desktops+
// bar reads to refuse widget reordering and bar edge moves. Widgets only get
// the plugin bar API, so the state comes from the public bar config and the
// toggle goes through the bar's IPC handler.
BarWidget {
  id: root
  moduleName: "desktops-plus.bar-lock"

  readonly property bool locked: !!(bar && bar.shell && bar.shell.barConfig && bar.shell.barConfig.locked === true)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.locked ? "󰌾" : "󰌿"
    tooltipText: root.locked ? "Unlock Bar Layout" : "Lock Bar Layout"
    dimmed: !root.locked
    opacity: root.locked ? 1 : 0.45
    useActiveColor: false
    fontSize: Style.font.caption
    horizontalMargin: 5
    verticalPadding: 5
    fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1
    onPressed: function() {
      if (root.bar) root.bar.run("omarchy-shell -q desktops-plus.bar toggleLock")
    }
  }
}
