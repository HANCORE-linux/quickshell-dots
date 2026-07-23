import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Fan-speed and temperature badge, installable on any Omarchy bar. Polls
// `sensors -j` (lm_sensors) every 30s; click opens a popup with per-fan RPM
// and per-sensor temperatures (CPU package, board, NVMe).
BarWidget {
  id: root
  moduleName: "local.fan-monitor"

  property var fans: []
  property var temps: []
  property bool loaded: false

  readonly property bool hasDeadFan: {
    var f = fans
    for (var i = 0; i < f.length; i++) { if (f[i].rpm === 0) return true }
    return false
  }

  function refresh() {
    if (!sensorsProc.running) sensorsProc.running = true
  }

  function parseSensors(raw) {
    try {
      var data = JSON.parse(raw)
      var newFans = []
      var newTemps = []
      var chips = Object.keys(data)

      for (var ci = 0; ci < chips.length; ci++) {
        var chip = chips[ci]
        var chipData = data[chip]
        if (typeof chipData !== "object" || chipData === null) continue
        var skeys = Object.keys(chipData)

        if (chip.indexOf("it8689") !== -1 || chip.indexOf("it87") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue

            if (sname.indexOf("fan") === 0) {
              var fk = sname + "_input"
              if (sval.hasOwnProperty(fk))
                newFans.push({ name: sname, rpm: Math.round(sval[fk]) })
            } else if (sname.indexOf("temp") === 0) {
              var tk = sname + "_input"
              if (sval.hasOwnProperty(tk)) {
                var t = sval[tk]
                if (t > -50 && t < 120)
                  newTemps.push({ name: "Board " + sname.replace("temp", ""), value: t.toFixed(1) })
              }
            }
          }
        } else if (chip.indexOf("coretemp") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            if (sname !== "Package id 0") continue
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue
            var vkeys = Object.keys(sval)
            for (var ki = 0; ki < vkeys.length; ki++) {
              if (vkeys[ki].indexOf("_input") !== -1) {
                newTemps.unshift({ name: "CPU", value: sval[vkeys[ki]].toFixed(1) })
                break
              }
            }
          }
        } else if (chip.indexOf("nvme") !== -1) {
          for (var si = 0; si < skeys.length; si++) {
            var sname = skeys[si]
            if (sname !== "Composite") continue
            var sval = chipData[sname]
            if (typeof sval !== "object" || sval === null) continue
            var vkeys = Object.keys(sval)
            for (var ki = 0; ki < vkeys.length; ki++) {
              if (vkeys[ki].indexOf("_input") !== -1) {
                var t = sval[vkeys[ki]]
                if (t > -50 && t < 100)
                  newTemps.push({ name: "NVMe " + chip.slice(-4), value: t.toFixed(1) })
                break
              }
            }
          }
        }
      }

      fans = newFans
      temps = newTemps
      loaded = true
    } catch (e) { /* keep last good value */ }
  }

  Process {
    id: sensorsProc
    command: ["sensors", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseSensors(text) }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  readonly property string tooltipText: {
    if (fans.length === 0) return "Fans & temps\nClick to view details"
    var parts = []
    for (var i = 0; i < fans.length; i++)
      parts.push(fans[i].name + ": " + (fans[i].rpm === 0 ? "STOPPED" : fans[i].rpm + " RPM"))
    return parts.join("\n") + "\nClick to view details"
  }

  function tempColor(t) {
    if (t >= 80) return Color.urgent
    if (t >= 65) return "#e8a33d"
    return Color.popups.text
  }

  // The bar's own primary/foreground color (Rise's palette, or whatever
  // Bar.qml uses on the built-in bar) rather than Omarchy's generic accent,
  // so the badge matches whichever bar it's installed on.
  readonly property color primaryColor: root.bar ? root.bar.barForeground : Color.foreground

  readonly property real worstTemp: {
    var w = -999
    for (var i = 0; i < temps.length; i++) {
      var v = parseFloat(temps[i].value)
      if (v > w) w = v
    }
    return w
  }

  // Badge color reflects temperature, not fan state: primary while normal,
  // amber once elevated, red only once actually too hot.
  function badgeColor() {
    if (worstTemp >= 80) return Color.urgent
    if (worstTemp >= 65) return "#e8a33d"
    return root.primaryColor
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰈐"   // md-fan (Nerd Font, U+F0210)
    slotSize: Style.bar.statusSlot
    fontSize: Style.bar.iconFont
    tooltipText: root.tooltipText
    activeColor: root.badgeColor()
    active: true
    onPressed: detail.open = !detail.open
  }

  PopupCard {
    id: detail
    anchorItem: button
    bar: root.bar
    owner: root
    contentWidth: Style.space(280)
    contentHeight: col.implicitHeight + padding * 2
    onOpenChanged: if (open) root.refresh()

    Column {
      id: col
      width: detail.contentWidth - detail.padding * 2
      spacing: Style.spacing.lg

      Row {
        width: parent.width
        spacing: Style.spacing.sm
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰈐"
          color: root.badgeColor()
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            text: "Fan Monitor"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            text: !root.loaded ? "Loading…" : (root.hasDeadFan ? "FAN STOPPED" : "All fans OK")
            color: root.hasDeadFan ? Color.urgent : root.primaryColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator { foreground: Color.popups.text }

      Column {
        width: parent.width
        spacing: Style.spacing.xs
        PanelSectionHeader { foreground: Color.popups.text; text: "FAN SPEEDS" }
        Repeater {
          model: root.fans
          Row {
            required property var modelData
            width: parent.width
            spacing: Style.spacing.sm
            Text {
              text: modelData.name
              color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
              width: 48
            }
            Text {
              text: modelData.rpm === 0 ? "STOPPED" : modelData.rpm + " RPM"
              color: modelData.rpm === 0 ? Color.urgent : Color.popups.text
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
              font.bold: modelData.rpm === 0
            }
          }
        }
      }

      PanelSeparator { foreground: Color.popups.text }

      Column {
        width: parent.width
        spacing: Style.spacing.xs
        PanelSectionHeader { foreground: Color.popups.text; text: "TEMPERATURES" }
        Repeater {
          model: root.temps
          Row {
            required property var modelData
            width: parent.width
            spacing: Style.spacing.sm
            readonly property real tempVal: parseFloat(modelData.value)
            Text {
              text: modelData.name
              color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.6)
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
              width: 76
            }
            Text {
              text: modelData.value + "°C"
              color: root.tempColor(parent.tempVal)
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
