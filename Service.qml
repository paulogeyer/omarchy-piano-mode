import QtQuick
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

  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string keepAlive: pluginDir + "/bin/keep-alive"
  readonly property string pianoMode: pluginDir + "/bin/piano-mode"
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string configPath: configHome + "/omarchy/piano-mode.json"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string flagPath: stateHome + "/omarchy/piano-mode/enabled"

  property bool settingsOpen: false
  property var cfg: Config.defaults()
  property var liveSinks: []
  property bool hydrating: false

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
  }

  function patch(mutator) {
    var next = Config.clone(cfg)
    mutator(next)
    cfg = next
    saveSoon.restart()
  }

  function movePriority(index, delta) {
    patch(function(next) {
      var list = next.sinkPriority.slice()
      var dest = index + delta
      if (dest < 0 || dest >= list.length) return
      var item = list[index]
      list.splice(index, 1)
      list.splice(dest, 0, item)
      next.sinkPriority = list
    })
  }

  function removePriority(index) {
    patch(function(next) {
      var list = next.sinkPriority.slice()
      list.splice(index, 1)
      next.sinkPriority = list
    })
  }

  function addPriority(pattern) {
    var item = String(pattern || "").trim()
    if (!item) return
    patch(function(next) {
      var list = next.sinkPriority.slice()
      for (var i = 0; i < list.length; i++)
        if (String(list[i]) === item) return
      list.push(item)
      next.sinkPriority = list
    })
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

  Process {
    id: sinksProc
    command: [root.keepAlive, "sinks"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.liveSinks = JSON.parse(String(text || "[]")) }
        catch (e) { root.liveSinks = [] }
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
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          contentWidth: width
          contentHeight: body.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

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
              text: "When piano mode is on, pick which output becomes the default. First match in the list wins. WU-BT10 AUDIO is first by default."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Toggle {
              width: parent.width
              label: "Change default output in piano mode"
              description: "Switch to the first available device in the priority list, then restore the previous output when piano mode turns off."
              checked: root.cfg.setDefaultSink === true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.patch(function(next) { next.setDefaultSink = !root.cfg.setDefaultSink })
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "OUTPUT PRIORITY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.cfg.sinkPriority

              Row {
                required property var modelData
                required property int index
                width: body.width
                spacing: Style.space(6)

                Text {
                  width: parent.width - Style.space(150)
                  elide: Text.ElideRight
                  text: String(modelData)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                  text: "Up"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  enabled: index > 0
                  onClicked: root.movePriority(index, -1)
                }
                Button {
                  text: "Down"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  enabled: index < root.cfg.sinkPriority.length - 1
                  onClicked: root.movePriority(index, 1)
                }
                Button {
                  text: "Remove"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.removePriority(index)
                }
              }
            }

            Text {
              visible: root.liveSinks.length > 0
              text: "Add a live output"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.liveSinks

                Button {
                  required property var modelData
                  text: String(modelData.description || modelData.name || "")
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.addPriority(text)
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
              onClicked: root.closeSettings()
            }
          }
        }
      }
    }
  }
}
