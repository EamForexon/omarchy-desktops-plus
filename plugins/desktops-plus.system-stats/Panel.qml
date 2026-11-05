import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "desktops-plus.system-stats"
  ipcTarget: "desktops-plus.system-stats"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Latest output of bin/system-stats.
  property var stats: ({})

  // Poll faster while the popup is visible.
  readonly property int refreshInterval: opened ? 1500 : 3000

  function open() {
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function temperatureColor(value) {
    var temperature = Number(value)
    var normal = root.bar ? root.bar.foreground : "white"
    if (value === undefined || value === "" || !isFinite(temperature)) return normal
    if (temperature >= 80) return "#f38ba8"
    if (temperature >= 70) return "#fab387"
    if (temperature >= 55) return "#f9e2af"
    return normal
  }

  function usageColor(value) {
    var usage = Number(value)
    var normal = root.bar ? root.bar.foreground : "white"
    if (!isFinite(usage)) return normal
    if (usage >= 90) return "#f38ba8"
    if (usage >= 75) return "#fab387"
    return normal
  }

  function value(key, suffix) {
    var v = stats[key]
    if (v === undefined || v === "" || v === "--") return "--"
    return v + (suffix || "")
  }

  Process {
    id: statsProcess
    command: [String(Qt.resolvedUrl("bin/system-stats")).replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.stats = JSON.parse(String(text || ""))
        } catch (error) {
          console.warn("desktops-plus.system-stats", "Could not parse hardware metrics", error)
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("desktops-plus.system-stats", "Metric script exited with status", exitCode)
    }
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statsProcess.running) statsProcess.running = true
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ---- One column per component: header, big usage + temperature, meter, details.
  component ComponentCard: Column {
    id: card
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string usage: "--"
    property string temperature: ""
    property var details: []

    spacing: Style.space(10)

    Row {
      spacing: Style.space(8)
      Text {
        text: card.icon
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        anchors.verticalCenter: parent.verticalCenter
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: card.title
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }
        Text {
          textFormat: Text.PlainText
          text: card.subtitle
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Row {
      spacing: Style.space(10)
      Row {
        spacing: Style.space(2)
        Text {
          id: usageBig
          textFormat: Text.PlainText
          text: card.usage
          color: root.usageColor(card.usage)
          font.family: root.bar.fontFamily
          font.pixelSize: 40
          font.bold: true
        }
        Text {
          text: card.usage === "--" ? "" : "%"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          anchors.top: usageBig.top
          anchors.topMargin: Style.space(6)
        }
      }
      Text {
        visible: card.temperature !== ""
        textFormat: Text.PlainText
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(6)
        text: card.temperature + "°C"
        color: root.temperatureColor(card.temperature)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
      }
    }

    Rectangle {
      width: Style.space(150)
      height: Style.space(4)
      radius: height / 2
      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)

      Rectangle {
        height: parent.height
        radius: parent.radius
        width: parent.width * Math.max(0, Math.min(100, Number(card.usage) || 0)) / 100
        color: root.usageColor(card.usage)
        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
      }
    }

    Grid {
      columns: 2
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(4)

      Repeater {
        model: card.details.length * 2
        Text {
          required property int index
          readonly property var entry: card.details[Math.floor(index / 2)]
          readonly property bool isLabel: index % 2 === 0
          textFormat: Text.PlainText
          text: isLabel ? entry[0] : entry[1]
          color: isLabel ? Qt.darker(root.bar.foreground, 1.5) : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: isLabel ? Style.font.caption : Style.font.body
          font.letterSpacing: isLabel ? 1 : 0
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(statsColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: statsColumn
        width: parent.width
        spacing: Style.space(14)

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(40)

          ComponentCard {
            icon: "󰻠"
            title: "CPU"
            subtitle: root.value("cpuName") + " · " + root.value("cpuThreads") + "T"
            usage: root.value("cpuUsage")
            temperature: root.value("cpuTemp")
            details: [
              ["FREQ", root.value("cpuFreq", " GHz")],
              ["PEAK", root.value("cpuFreqMax", " GHz")],
              ["LOAD", root.value("load1") + " " + root.value("load5")]
            ]
          }

          ComponentCard {
            icon: "󰢮"
            title: "GPU"
            subtitle: root.value("gpuName")
            usage: root.value("gpuUsage")
            temperature: root.value("gpuTemp")
            details: [
              ["VRAM", root.value("vramUsed") + " / " + root.value("vramTotal", " GB")],
              ["POWER", root.value("gpuPower") + " / " + root.value("gpuPowerLimit", " W")],
              ["CLOCK", root.value("gpuClock", " MHz")],
              ["FAN", root.value("gpuFan", "%")]
            ]
          }

          ComponentCard {
            icon: "󰍛"
            title: "RAM"
            subtitle: root.value("ramTotal", " GB total")
            usage: root.value("ramUsage")
            details: [
              ["USED", root.value("ramUsed") + " / " + root.value("ramTotal", " GB")],
              ["FREQ", root.value("ramSpeed", " MT/s")],
              ["SWAP", root.value("swapUsed") + " / " + root.value("swapTotal", " GB")]
            ]
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.bar.foreground
          opacity: 0.12
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(44)

          Repeater {
            model: [
              ["󰋊", "DISK /", root.value("diskUsed") + " / " + root.value("diskTotal", " GB") + "  " + root.value("diskUsage", "%"), ""],
              ["", "NVME", root.value("diskTemp", "°C"), root.value("diskTemp")],
              ["󰔟", "UPTIME", root.value("uptime"), ""],
              ["󰚥", "POWER", root.value("systemPower", "W"), ""]
            ]

            Row {
              required property var modelData
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData[0]
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
              }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  visible: modelData[1] !== ""
                  text: modelData[1]
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  textFormat: Text.PlainText
                  text: modelData[2]
                  color: modelData[3] !== "" ? root.temperatureColor(modelData[3]) : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
