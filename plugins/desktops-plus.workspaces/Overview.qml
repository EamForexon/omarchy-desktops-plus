import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Overview of every workspace, shown on every monitor at once: each monitor
// lists its own workspaces. Cards keep the monitor's real proportions, and
// each window is a box at its real position with its icon and title.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // [{ name, width, height, workspaces: [{ id, focused, visible, windows: [...] }] }]
  property var monitors: []
  readonly property string iconsScript: String(Qt.resolvedUrl("bin/icons.sh")).replace(/^file:\/\//, "")

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding + Style.space(12)
  property int cardSpacing: Style.space(24)

  // Output that had focus when opened; it takes the keyboard.
  property string focusedScreen: ""

  function open(payloadJson) {
    root.focusedScreen = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    snapshot.running = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "desktops-plus.workspaces")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function dispatch(expr) {
    Quickshell.execDetached(["hyprctl", "dispatch", expr])
  }

  function focusWorkspace(id) {
    root.dismiss()
    root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  function focusWindow(address) {
    root.dismiss()
    root.dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })")
  }

  function closeWindow(address) {
    root.dispatch("hl.dsp.window.close({ window = \"address:" + address + "\" })")
    // Let the app go away (or ask to save) before redrawing.
    refreshLater.restart()
  }

  Timer {
    id: refreshLater
    interval: 400
    onTriggered: if (root.opened) snapshot.running = true
  }

  // An app's icon: Simple Icons brand tinted to the text color, a Nerd Font
  // glyph, the app's own icon in grayscale, or its initial as a last resort.
  component AppIcon: Item {
    id: icon
    property var app: ({})
    property real size: 16
    property real strength: 1
    readonly property string source: app.mono || app.color || ""
    width: size
    height: size

    // Kept as a hidden layer so the effect can sample it.
    Image {
      id: image
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(icon.size * 2)
      sourceSize.height: Math.round(icon.size * 2)
      source: icon.source
      asynchronous: true
      visible: false
    }

    MultiEffect {
      anchors.fill: image
      source: image
      visible: icon.source !== "" && !icon.app.glyph && image.status === Image.Ready
      // Simple Icons SVGs are black: lift to white, then tint.
      brightness: icon.app.mono ? 1.0 : 0.0
      colorization: icon.app.mono ? 1.0 : 0.0
      colorizationColor: root.foreground
      saturation: icon.app.mono ? 0.0 : -1.0
      opacity: icon.strength
    }

    Text {
      anchors.centerIn: parent
      visible: !!icon.app.glyph || icon.source === "" || image.status === Image.Error
      textFormat: Text.PlainText
      text: icon.app.glyph || String(icon.app.appClass || "?").replace(/^.*\./, "").charAt(0).toUpperCase()
      color: root.foreground
      opacity: icon.strength
      font.family: icon.app.glyph ? "JetBrainsMono Nerd Font" : root.fontFamily
      font.pixelSize: icon.size * (icon.app.glyph ? 1.0 : 0.8)
      font.bold: !icon.app.glyph
    }
  }

  // Where the fullscreen window tiles when it isn't fullscreen. Hyprland only
  // reports the fullscreen geometry, so take the bounding box of the work area
  // left uncovered by the other windows (a rectangle in tiling layouts).
  function freeSlot(windows, monitor, gapsOut) {
    if (windows.length === 0) return null
    var r = monitor.reserved
    var area = { l: r[0] + gapsOut, t: r[1] + gapsOut, r: monitor.width - r[2] - gapsOut, b: monitor.height - r[3] - gapsOut }
    var xs = [area.l, area.r], ys = [area.t, area.b]
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      xs.push(w.x, w.x + w.width)
      ys.push(w.y, w.y + w.height)
    }
    var num = function(a, b) { return a - b }
    xs.sort(num); ys.sort(num)
    var minCell = 40, pad = 20
    var box = null
    for (var xi = 0; xi < xs.length - 1; xi++) {
      for (var yi = 0; yi < ys.length - 1; yi++) {
        var x0 = xs[xi], x1 = xs[xi + 1], y0 = ys[yi], y1 = ys[yi + 1]
        if (x1 - x0 < minCell || y1 - y0 < minCell) continue
        if (x0 < area.l - 1 || x1 > area.r + 1 || y0 < area.t - 1 || y1 > area.b + 1) continue
        var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        var taken = windows.some(function(w) {
          return cx > w.x - pad && cx < w.x + w.width + pad && cy > w.y - pad && cy < w.y + w.height + pad
        })
        if (taken) continue
        box = box
          ? { l: Math.min(box.l, x0), t: Math.min(box.t, y0), r: Math.max(box.r, x1), b: Math.max(box.b, y1) }
          : { l: x0, t: y0, r: x1, b: y1 }
      }
    }
    if (!box) return null
    // Leave the usual gap where the slot meets another window (gaps_in on both
    // sides plus borders, as measured between tiled windows).
    var gap = 14, edge = 4
    if (box.l > area.l + edge) box.l += gap
    if (box.t > area.t + edge) box.t += gap
    if (box.r < area.r - edge) box.r -= gap
    if (box.b < area.b - edge) box.b -= gap
    return { x: box.l, y: box.t, width: box.r - box.l, height: box.b - box.t }
  }

  // App names that windows tack onto their titles, besides class/initialTitle.
  readonly property var appNames: [
    "Mozilla Firefox", "Firefox", "Chromium", "Google Chrome", "Brave",
    "Code - OSS", "Visual Studio Code", "Claude Code",
    "Godot Engine", "Godot", "Discord", "Vesktop", "Spotify", "Obsidian"
  ]
  readonly property var terminalTitles: ["foot", "alacritty", "kitty", "ghostty", "wezterm"]
  // Apps whose useful part is the last segment, e.g. "main.tscn - MyGame - Godot Engine".
  readonly property var lastSegmentClasses: ["godot"]
  readonly property var separator: /\s+[—–\-|·:]\s+/

  function stripStatus(text) {
    // Spinners/markers like "✳ ◐ ●" and unread counters like "(1248)".
    return String(text || "").replace(/^[^A-Za-z0-9\u00C0-\u024F\u0400-\u04FF(@#]+/, "").replace(/^\(\d+\)\s*/, "").trim()
  }

  function windowLabel(c) {
    var title = root.stripStatus(c.title)
    var names = root.appNames.slice()
    if (c.class) names.push(c.class)
    var initial = root.stripStatus(c.initialTitle)
    if (initial && !root.separator.test(initial)) names.push(initial)
    names.sort(function(a, b) { return b.length - a.length })

    var changed = true
    while (changed && title) {
      changed = false
      for (var i = 0; i < names.length; i++) {
        var esc = names[i].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        var next = title.replace(new RegExp("\\s+[—–\\-|·:]\\s+" + esc + "$", "i"), "")
          .replace(new RegExp("^" + esc + "\\s+[—–\\-|·:]\\s+", "i"), "")
        if (next !== title) { title = next.trim(); changed = true }
      }
    }

    if (root.lastSegmentClasses.indexOf(String(c.class || "").toLowerCase()) !== -1) {
      var parts = title.split(root.separator)
      title = parts[parts.length - 1]
    }

    if (!title) title = initial || c.class || ""
    // Terminals that don't set a title just say "foot"; the app id says more
    // (org.omarchy.btop -> btop).
    if (root.terminalTitles.indexOf(title.toLowerCase()) !== -1 && c.class && c.class.toLowerCase() !== title.toLowerCase())
      title = String(c.class).replace(/^.*\./, "")
    return title.replace(/^\*\s*|\s*\(\*\)$/g, "")
  }

  function build(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { return }

    var icons = data.icons || {}
    var gapsOut = data.gaps && data.gaps.css ? parseInt(String(data.gaps.css).split(" ")[0]) || 0 : 0
    var focusedWs = -1
    var result = []
    var byName = {}
    data.monitors.sort(function(a, b) { return a.x - b.x || a.y - b.y })
    for (var i = 0; i < data.monitors.length; i++) {
      var m = data.monitors[i]
      var rotated = m.transform % 2 === 1
      var w = (rotated ? m.height : m.width) / m.scale
      var h = (rotated ? m.width : m.height) / m.scale
      if (m.focused) focusedWs = m.activeWorkspace.id
      var mon = { name: m.name, x: m.x, y: m.y, width: w, height: h, active: m.activeWorkspace.id, reserved: m.reserved || [0, 0, 0, 0], workspaces: [] }
      byName[m.name] = mon
      result.push(mon)
    }

    var wsById = {}
    data.workspaces.sort(function(a, b) { return a.id - b.id })
    for (var j = 0; j < data.workspaces.length; j++) {
      var ws = data.workspaces[j]
      var owner = byName[ws.monitor]
      if (ws.id < 1 || !owner) continue
      // fullscreen: 0 none, 1 maximized, 2 fullscreen; covered = windows hidden behind it.
      var entry = { id: ws.id, focused: ws.id === focusedWs, visible: ws.id === owner.active, windows: [], fullscreen: 0, covered: [], slot: null }
      wsById[ws.id] = { entry: entry, monitor: owner }
      owner.workspaces.push(entry)
    }

    for (var k = 0; k < data.clients.length; k++) {
      var c = data.clients[k]
      var slot = wsById[c.workspace.id]
      if (!slot || c.hidden) continue
      slot.entry.windows.push({
        address: c.address,
        appClass: c.class,
        active: c.focusHistoryID === 0,
        glyph: icons[c.address] && icons[c.address].glyph ? String.fromCodePoint(parseInt(icons[c.address].glyph, 16)) : "",
        mono: icons[c.address] && icons[c.address].mono ? "file://" + icons[c.address].mono : "",
        color: icons[c.address] && icons[c.address].color ? "file://" + icons[c.address].color : "",
        label: root.windowLabel(c),
        x: c.at[0] - slot.monitor.x,
        y: c.at[1] - slot.monitor.y,
        width: c.size[0],
        height: c.size[1],
        floating: c.floating,
        fullscreen: c.fullscreen || 0
      })
    }

    for (var id in wsById) {
      var e = wsById[id].entry
      // A fullscreen/maximized window hides the rest, as on screen: draw only it.
      var full = e.windows.filter(function(w) { return w.fullscreen > 0 })
      if (full.length > 0) {
        full.sort(function(a, b) { return b.fullscreen - a.fullscreen })
        e.fullscreen = full[0].fullscreen
        e.covered = e.windows.filter(function(w) { return w !== full[0] })
        e.slot = root.freeSlot(e.covered, wsById[id].monitor, gapsOut)
        e.windows = [full[0]]
        continue
      }
      // Floating windows on top of tiled ones, as on screen.
      e.windows.sort(function(a, b) { return (a.floating ? 1 : 0) - (b.floating ? 1 : 0) })
    }

    // Empty workspaces are left out.
    for (var r = 0; r < result.length; r++) {
      result[r].workspaces = result[r].workspaces.filter(function(ws) { return ws.windows.length > 0 })
    }

    root.monitors = result
    root.opened = true
  }

  Process {
    id: snapshot
    command: ["sh", "-c", "c=$(hyprctl -j clients); jq -n --argjson m \"$(hyprctl -j monitors)\" --argjson w \"$(hyprctl -j workspaces)\" --argjson c \"$c\" --argjson i \"$(printf '%s' \"$c\" | \"$0\")\" --argjson g \"$(hyprctl -j getoption general:gaps_out)\" '{monitors: $m, workspaces: $w, clients: $c, icons: $i, gaps: $g}'", root.iconsScript]
    stdout: StdioCollector {
      onStreamFinished: root.build(text)
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      readonly property bool hasFocus: modelData.name === root.focusedScreen
      // This monitor's entry only.
      readonly property var monitors: root.monitors.filter(function(m) { return m.name === panel.modelData.name })

      // Fit this monitor's row of cards to its width.
      readonly property real scale: {
        var avail = panel.width * 0.85 - root.contentMargin * 2
        var s = 0.18
        for (var i = 0; i < monitors.length; i++) {
          var n = monitors[i].workspaces.length
          if (n > 0) s = Math.min(s, (avail - (n - 1) * root.cardSpacing) / (n * monitors[i].width))
        }
        return Math.max(0.02, s)
      }

      visible: root.opened
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "desktops-plus-overview"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: hasFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      onVisibleChanged: if (visible && hasFocus) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

      Rectangle {
        anchors.fill: parent
        color: root.scrim
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }

      BorderSurface {
        id: card
        width: content.implicitWidth + root.contentMargin * 2
        height: content.implicitHeight + root.contentMargin * 2
        radius: root.cornerRadius
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        padding: root.contentMargin

        MouseArea { anchors.fill: parent; onClicked: {} }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: true
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.dismiss()
              event.accepted = true
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
              root.focusWorkspace(event.key - Qt.Key_0)
              event.accepted = true
            } else if (event.key === Qt.Key_0) {
              root.focusWorkspace(10)
              event.accepted = true
            }
          }
        }

        Column {
          id: content
          anchors.centerIn: parent
          spacing: root.cardSpacing

          Repeater {
            model: panel.monitors

            Column {
              id: monitorRow
              required property var modelData
              spacing: Style.space(12)

              Text {
                textFormat: Text.PlainText
                text: monitorRow.modelData.name + "  ·  " + Math.round(monitorRow.modelData.width) + "×" + Math.round(monitorRow.modelData.height)
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Row {
                spacing: root.cardSpacing

                Repeater {
                  model: monitorRow.modelData.workspaces

                  Column {
                    id: wsCard
                    required property var modelData
                    spacing: Style.space(8)

                    Rectangle {
                      id: screenBox
                      width: monitorRow.modelData.width * panel.scale
                      height: monitorRow.modelData.height * panel.scale
                      radius: Style.space(3)
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                      border.width: wsCard.modelData.focused ? 2 : 1
                      // Visible workspaces get a white frame, the rest gray; contents stay at full strength.
                      border.color: wsCard.modelData.focused || wsCard.modelData.visible
                        ? root.foreground
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
                      clip: true

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.focusWorkspace(wsCard.modelData.id)
                      }

                      // Fullscreen/maximized: a minimap of the workspace layout in the
                      // corner. Hidden windows sit at their real spots with their icons;
                      // the hatched space left over is where the fullscreen app tiles.
                      Rectangle {
                        id: minimap
                        z: 10
                        visible: wsCard.modelData.fullscreen > 0
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Style.space(8)
                        width: Math.round(screenBox.width * 0.32)
                        height: Math.round(width * monitorRow.modelData.height / monitorRow.modelData.width)
                        readonly property real mapScale: width / monitorRow.modelData.width
                        color: "transparent"

                        // The fullscreen app's own slot, hatched.
                        Rectangle {
                          visible: !!wsCard.modelData.slot
                          x: wsCard.modelData.slot ? wsCard.modelData.slot.x * minimap.mapScale : 0
                          y: wsCard.modelData.slot ? wsCard.modelData.slot.y * minimap.mapScale : 0
                          width: wsCard.modelData.slot ? wsCard.modelData.slot.width * minimap.mapScale : 0
                          height: wsCard.modelData.slot ? wsCard.modelData.slot.height * minimap.mapScale : 0
                          radius: Style.space(1)
                          color: root.background
                          border.width: 1
                          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
                          clip: true

                          Canvas {
                            id: hatch
                            anchors.fill: parent
                            anchors.margins: 1
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onPaint: {
                              var ctx = getContext("2d")
                              ctx.reset()
                              ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                              ctx.lineWidth = 1
                              var step = 6
                              ctx.beginPath()
                              for (var d = -height; d < width; d += step) {
                                ctx.moveTo(d, height)
                                ctx.lineTo(d + height, 0)
                              }
                              ctx.stroke()
                            }
                          }
                        }

                        Repeater {
                          model: wsCard.modelData.covered

                          Rectangle {
                            id: mini
                            required property var modelData
                            x: modelData.x * minimap.mapScale
                            y: modelData.y * minimap.mapScale
                            width: modelData.width * minimap.mapScale
                            height: modelData.height * minimap.mapScale
                            radius: Style.space(1)
                            color: root.background
                            border.width: 1
                            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)

                            AppIcon {
                              anchors.centerIn: parent
                              app: mini.modelData
                              size: Math.max(8, Math.min(Style.space(22), mini.width * 0.6, mini.height * 0.6))
                              strength: 0.8
                            }
                          }
                        }
                      }

                      Repeater {
                        model: wsCard.modelData.windows

                        Rectangle {
                          id: win
                          required property var modelData
                          x: modelData.x * panel.scale
                          y: modelData.y * panel.scale
                          width: Math.max(4, modelData.width * panel.scale)
                          height: Math.max(4, modelData.height * panel.scale)
                          radius: Style.space(2)
                          readonly property real iconSize: Math.max(8, Math.min(Style.space(32), width * 0.5, height * 0.5))
                          color: winMouse.containsMouse ? root.selectedBackground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                          // Like Hyprland's borders: white for the focused window, gray otherwise.
                          readonly property color tone: modelData.active
                            ? root.foreground
                            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.6)
                          border.width: 1
                          border.color: tone

                          Column {
                            anchors.centerIn: parent
                            width: win.width - Style.space(20)
                            spacing: Style.space(12)

                            AppIcon {
                              anchors.horizontalCenter: parent.horizontalCenter
                              app: win.modelData
                              size: win.iconSize
                              strength: win.tone.a
                            }

                            Text {
                              width: parent.width
                              // Only when there's room under the icon.
                              visible: win.height >= win.iconSize + implicitHeight + Style.space(28)
                              textFormat: Text.PlainText
                              text: win.modelData.label
                              horizontalAlignment: Text.AlignHCenter
                              elide: Text.ElideRight
                              color: root.foreground
                              opacity: win.tone.a
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.small || Math.round(Style.font.body * 0.8)
                            }
                          }

                          MouseArea {
                            id: winMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: function(mouse) {
                              if (mouse.button === Qt.LeftButton) root.focusWindow(win.modelData.address)
                            }
                            // Double middle-click closes the window and keeps the overview open.
                            onDoubleClicked: function(mouse) {
                              if (mouse.button === Qt.MiddleButton) root.closeWindow(win.modelData.address)
                            }
                          }
                        }
                      }
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      text: wsCard.modelData.id === 10 ? "0" : String(wsCard.modelData.id)
                      color: root.foreground
                      opacity: wsCard.modelData.focused ? 1 : 0.6
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: wsCard.modelData.focused
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
