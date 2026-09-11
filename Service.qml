import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Config.js" as Config

// Runs the WU-BT10 keep-alive and hosts piano-mode settings.
Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  // Omarchy strips __sourceDir from the public manifest. Fall back to the
  // install path so keep-alive still starts.
  readonly property string pluginDir: {
    var fromManifest = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (fromManifest !== "") return fromManifest
    return configHome + "/omarchy/plugins/casio.wu-bt10-piano"
  }
  readonly property string keepAlive: pluginDir + "/bin/keep-alive"
  readonly property string pianoMode: pluginDir + "/bin/piano-mode"
  readonly property string configPath: configHome + "/omarchy/piano-mode.json"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string flagPath: stateHome + "/omarchy/piano-mode/enabled"

  property bool settingsOpen: false
  property var cfg: Config.defaults()
  property var liveSinks: []
  property bool hydrating: false
  property bool dragging: false
  property bool pianoOn: false
  property bool audioOn: false
  property bool midiOn: false
  property bool audioExpected: false
  property string notifiedMissing: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.family

  function toggle() {
    if (pluginDir === "" || toggleProc.running) return
    toggleProc.command = [pianoMode, "toggle"]
    toggleProc.running = true
  }

  function openSettings() {
    hydrating = true
    settingsFile.reload()
    sinksProc.running = true
    settingsOpen = true
    Qt.callLater(function() {
      if (root.settingsOpen) keyCatcher.forceActiveFocus()
    })
  }

  function closeSettings() {
    settingsOpen = false
  }

  function applyLoaded(raw) {
    cfg = Config.parse(raw)
    hydrating = false
    rebuildDeviceList()
  }

  function patch(mutator) {
    var next = Config.clone(cfg)
    mutator(next)
    cfg = next
    saveSoon.restart()
  }

  function patternKey(value) {
    return String(value || "").trim().toLowerCase()
  }

  function sinkMatches(sink, pattern) {
    var pat = patternKey(pattern)
    if (!pat || !sink) return false
    return patternKey(sink.name).indexOf(pat) !== -1
        || patternKey(sink.description).indexOf(pat) !== -1
  }

  function isBluetoothSink(sink) {
    if (!sink) return false
    if (sink.bluetooth === true) return true
    if (sink.bluetooth === false) return false
    var name = patternKey(sink.name)
    return name.indexOf("bluez") !== -1 || name.indexOf("wu-bt10") !== -1
  }

  function isWiredFallback(pattern) {
    var p = patternKey(pattern)
    return p === "hdmi" || p === "headphones" || p === "speaker"
  }

  function keepPattern(pattern) {
    var pat = String(pattern || "").trim()
    if (!pat) return false
    if (patternKey(pat) === patternKey(cfg.audioName)) return true
    var matchedBt = false
    var matchedWired = false
    for (var i = 0; i < liveSinks.length; i++) {
      var s = liveSinks[i]
      if (!sinkMatches(s, pat)) continue
      if (isBluetoothSink(s)) matchedBt = true
      else matchedWired = true
    }
    if (matchedBt) return true
    if (matchedWired) return false
    return !isWiredFallback(pat)
  }

  function rebuildDeviceList() {
    if (dragging) return
    var list = []
    var seen = {}

    function add(label, available) {
      var text = String(label || "").trim()
      if (!text) return
      var key = patternKey(text)
      if (seen[key]) {
        if (available) {
          for (var i = 0; i < list.length; i++) {
            if (patternKey(list[i].label) === key)
              list[i].available = true
          }
        }
        return
      }
      seen[key] = true
      list.push({ label: text, available: !!available })
    }

    var pri = (cfg && cfg.sinkPriority) ? cfg.sinkPriority : []
    for (var i = 0; i < pri.length; i++) {
      if (!keepPattern(pri[i])) continue
      var avail = false
      for (var j = 0; j < liveSinks.length; j++) {
        if (!isBluetoothSink(liveSinks[j])) continue
        if (sinkMatches(liveSinks[j], pri[i])) {
          avail = liveSinks[j].available !== false
          break
        }
      }
      add(pri[i], avail)
    }
    for (var k = 0; k < liveSinks.length; k++) {
      var s = liveSinks[k]
      if (!isBluetoothSink(s)) continue
      add(s.description || s.name, s.available !== false)
    }
    if (cfg && cfg.audioName) add(cfg.audioName, false)

    deviceModel.clear()
    for (var n = 0; n < list.length; n++)
      deviceModel.append(list[n])
  }

  function persistDeviceOrder() {
    var list = []
    for (var i = 0; i < deviceModel.count; i++)
      list.push(deviceModel.get(i).label)
    hydrating = false
    var next = Config.clone(cfg)
    next.sinkPriority = list
    cfg = next
    settingsFile.setText(Config.stringify(cfg))
    applyPriority()
  }

  function applyPriority() {
    if (pluginDir === "" || applyProc.running) return
    applyProc.command = [keepAlive, "apply"]
    applyProc.running = true
  }

  function missingKey() {
    if (!pianoOn) return ""
    if (!audioOn && !midiOn) return "both-missing"
    if (audioOn && !midiOn) return "only-audio"
    if (!audioOn && midiOn) return "only-midi"
    return ""
  }

  function applyStatus(raw) {
    var info = {}
    try { info = JSON.parse(String(raw || "{}")) } catch (e) { return }
    var wasOn = pianoOn
    pianoOn = info.enabled === true || info.pianoMode === true
    audioOn = info.audioConnected === true
    midiOn = info.midiConnected === true
    audioExpected = info.audioExpected === true
    if (pianoOn && !wasOn) {
      notifiedMissing = ""
      notifyGrace.restart()
      return
    }
    if (!pianoOn) {
      notifiedMissing = ""
      notifyGrace.stop()
      return
    }
    if (notifyGrace.running) return
    notifyIfMissing()
  }

  function notifyIfMissing() {
    var key = missingKey()
    if (!key) {
      notifiedMissing = ""
      return
    }
    if (key === notifiedMissing) return
    notifiedMissing = key
    var title = "Restart the piano"
    var body = "Only WU-BT10 AUDIO is up. Restart the piano so AUDIO and MIDI both connect."
    var urgency = "normal"
    if (key === "both-missing") {
      title = "Piano looks off"
      body = "WU-BT10 AUDIO and MIDI were not found. The piano is probably turned off."
    } else if (key === "only-midi") {
      body = "Only WU-BT10 MIDI is up. Restart the piano so AUDIO and MIDI both connect."
    }
    Quickshell.execDetached([
      "notify-send",
      "--app-name=Piano Mode",
      "--urgency=" + urgency,
      "--expire-time=10000",
      "--icon=audio-headphones",
      "--replace-id=42110",
      title,
      body
    ])
  }

  function moveDevice(from, to) {
    if (from === to || from < 0 || to < 0 || to >= deviceModel.count) return
    dragging = true
    deviceModel.move(from, to, 1)
    dragging = false
    persistDeviceOrder()
  }

  function dropIndex(wrapItem, rowItem) {
    if (!wrapItem || !rowItem) return 0
    var p = rowItem.mapToItem(deviceList, 0, rowItem.height / 2)
    var h = wrapItem.height
    if (h <= 0) return 0
    var dest = Math.round((p.y - h / 2) / h)
    return Math.max(0, Math.min(deviceModel.count - 1, dest))
  }

  ListModel {
    id: deviceModel
  }

  Timer {
    id: saveSoon
    interval: 180
    repeat: false
    onTriggered: {
      if (root.hydrating) return
      settingsFile.setText(Config.stringify(root.cfg))
    }
  }

  FileView {
    id: settingsFile
    path: root.configPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyLoaded(text())
    onLoadFailed: root.applyLoaded("")
  }

  Process {
    id: keepAliveProc
    command: [root.keepAlive]
    running: root.pluginDir !== ""
    onExited: if (root.pluginDir !== "") keepAliveRestart.restart()
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).trim() !== "")
          console.log("casio.wu-bt10-piano", String(line).trim())
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("casio.wu-bt10-piano", text.trim())
    }
  }

  Timer {
    id: keepAliveRestart
    interval: 5000
    repeat: false
    onTriggered: keepAliveProc.running = true
  }

  Process {
    id: toggleProc
    running: false
  }

  Timer {
    interval: 2000
    running: root.pluginDir !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!healthProc.running) healthProc.running = true
  }

  Timer {
    id: notifyGrace
    interval: 12000
    repeat: false
    onTriggered: root.notifyIfMissing()
  }

  Process {
    id: healthProc
    command: [root.pianoMode, "status", "--json"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(String(text || "{}"))
    }
  }

  Process {
    id: applyProc
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).trim() !== "")
          console.log("casio.wu-bt10-piano", String(line).trim())
      }
    }
  }

  Process {
    id: sinksProc
    command: [root.keepAlive, "sinks"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "[]"))
          var only = []
          for (var i = 0; i < parsed.length; i++) {
            if (root.isBluetoothSink(parsed[i]))
              only.push(parsed[i])
          }
          root.liveSinks = only
        } catch (e) {
          root.liveSinks = []
        }
        root.rebuildDeviceList()
      }
    }
  }

  IpcHandler {
    target: "casio.wu-bt10-piano"
    function toggle(): void { root.toggle() }
    function on(): void {
      if (root.pluginDir === "") return
      toggleProc.command = [root.pianoMode, "on"]
      toggleProc.running = true
    }
    function off(): void {
      if (root.pluginDir === "") return
      toggleProc.command = [root.pianoMode, "off"]
      toggleProc.running = true
    }
    function settings(): void { root.openSettings() }
  }

  PanelWindow {
    visible: root.settingsOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "casio-wu-bt10-piano"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea { anchors.fill: parent; onClicked: root.closeSettings() }
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(460), parent.width - Style.space(48))
      height: Math.min(body.implicitHeight + Style.spacing.panelPadding * 2, parent.height - Style.space(48))
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.closeSettings()

        Flickable {
          id: settingsFlickable
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          contentWidth: width
          contentHeight: body.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: !root.dragging

          Column {
            id: body
            width: parent.width
            spacing: Style.space(12)

            Text {
              text: "Piano Mode"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "When piano mode is on, the first device in this list is connected and becomes the output. Other Bluetooth audio may be disconnected so it can connect. MIDI stays on either way."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Toggle {
              width: parent.width
              label: "Auto piano mode"
              description: "Turn on when the WU-BT10 dongle is seen, and off when it disappears. After you turn it off by hand, it stays off until the piano is powered off and on again."
              checked: root.cfg.autoEnable === true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.patch(function(next) { next.autoEnable = !root.cfg.autoEnable })
            }

            Toggle {
              width: parent.width
              label: "Change default output in piano mode"
              description: "Switch to the first available Bluetooth device in the list, then restore the previous output when piano mode turns off."
              checked: root.cfg.setDefaultSink === true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.patch(function(next) { next.setDefaultSink = !root.cfg.setDefaultSink })
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "BLUETOOTH OUTPUTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Drag a row to change priority. First in the list is connected and used."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: deviceModel.count === 0
              width: parent.width
              wrapMode: Text.WordWrap
              text: "No Bluetooth audio devices found."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              id: deviceList
              width: parent.width
              spacing: 0

              Repeater {
                model: deviceModel

                Item {
                  id: wrap
                  required property int index
                  required property string label
                  required property bool available
                  width: deviceList.width
                  height: Style.space(44)
                  z: dragArea.drag.active ? 2 : 0

                  Rectangle {
                    id: row
                    width: parent.width
                    height: parent.height
                    radius: Style.cornerRadius
                    color: dragArea.drag.active
                           ? Qt.alpha(root.accent, 0.18)
                           : (dragArea.containsMouse ? Qt.alpha(root.foreground, 0.08) : "transparent")

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(8)
                      spacing: Style.space(10)

                      Text {
                        text: "\u2261"
                        color: Qt.darker(root.foreground, 1.25)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        width: Style.space(22)
                        text: String(index + 1)
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Column {
                        width: parent.width - Style.space(80)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: String(label)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                        }

                        Text {
                          text: available ? "connected" : "not connected"
                          color: Qt.darker(root.foreground, 1.5)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                    }

                    MouseArea {
                      id: dragArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                      drag.target: row
                      drag.axis: Drag.YAxis
                      drag.smoothed: false
                      onPressed: root.dragging = true
                      onReleased: {
                        var dest = root.dropIndex(wrap, row)
                        row.y = 0
                        root.dragging = false
                        root.moveDevice(index, dest)
                      }
                      onCanceled: {
                        row.y = 0
                        root.dragging = false
                      }
                    }
                  }
                }
              }
            }

            Button {
              text: "Done"
              bordered: true
              active: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: {
                root.persistDeviceOrder()
                root.closeSettings()
              }
            }
          }
        }
      }
    }
  }
}
