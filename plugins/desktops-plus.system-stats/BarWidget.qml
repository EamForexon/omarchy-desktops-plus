import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "desktops-plus.system-stats"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (see desktops-plus.weather).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property var stats: panelLoader.item ? panelLoader.item.stats : ({})
  readonly property color normalColor: bar ? bar.foreground : "white"
  readonly property string metricsFont: bar ? bar.fontFamily : "monospace"
  readonly property int metricFontSize: Style.font.body
  readonly property int metricIconSize: Style.bar.iconFont

  function temperatureColor(value) {
    return panelLoader.item ? panelLoader.item.temperatureColor(value) : normalColor
  }

  function formatPercent(value) {
    var usage = Number(value)
    if (value === undefined || value === "" || !isFinite(usage)) return "--"
    var rounded = Math.round(usage)
    return (rounded < 10 ? "0" : "") + rounded + "%"
  }

  implicitWidth: metrics.implicitWidth
  implicitHeight: bar ? bar.barSize : 26

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  TextMetrics {
    id: usageTextMetrics
    font.family: root.metricsFont
    font.pixelSize: root.metricFontSize
    text: "00%"
  }
  TextMetrics {
    id: maxUsageTextMetrics
    font.family: root.metricsFont
    font.pixelSize: root.metricFontSize
    text: "100%"
  }
  TextMetrics {
    id: temperatureTextMetrics
    font.family: root.metricsFont
    font.pixelSize: root.metricFontSize
    text: "100°"
  }

  // Invisible-label button: provides click registration, cursor and panel anchor.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    labelVisible: false
    fixedWidth: metrics.implicitWidth
    tooltipText: ""

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) root.bar.run("omarchy-launch-or-focus-tui btop")
      else root.togglePanel()
    }
  }

  Row {
    id: metrics
    anchors.centerIn: parent
    spacing: 14

    Repeater {
      model: [
        { icon: "󰻠", usage: "cpuUsage", temp: "cpuTemp" },
        { icon: "󰢮", usage: "gpuUsage", temp: "gpuTemp" },
        { icon: "󰍛", usage: "ramUsage", temp: "" }
      ]

      Row {
        required property var modelData
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter

        Text { text: modelData.icon; color: root.normalColor; font.family: root.metricsFont; font.pixelSize: root.metricIconSize }
        Text {
          text: root.formatPercent(root.stats[modelData.usage])
          color: root.normalColor
          font.family: root.metricsFont
          font.pixelSize: root.metricFontSize
          horizontalAlignment: Text.AlignRight
          width: text === "100%" ? maxUsageTextMetrics.advanceWidth : usageTextMetrics.advanceWidth
        }
        Text {
          visible: modelData.temp !== ""
          text: (root.stats[modelData.temp] || "--") + "°"
          color: root.temperatureColor(root.stats[modelData.temp])
          font.family: root.metricsFont
          font.pixelSize: root.metricFontSize
          horizontalAlignment: Text.AlignRight
          width: temperatureTextMetrics.advanceWidth
        }
      }
    }

    Item {
      width: 16
      height: 1
    }
  }
}
