import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "casio.wu-bt10-piano"

  property bool pianoOn: false
  property bool audioOn: false
  property bool midiOn: false

  readonly property string pluginDir: {
    var home = Quickshell.env("HOME") || ""
    var configHome = Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    return configHome + "/omarchy/plugins/casio.wu-bt10-piano"
  }
  readonly property string pianoMode: pluginDir + "/bin/piano-mode"

  implicitWidth: vertical ? barSize : Style.bar.iconSlot
  implicitHeight: vertical ? Style.bar.iconSlot : barSize

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (toggleProc.running) return
    toggleProc.command = [pianoMode, "toggle"]
    toggleProc.running = true
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: [root.pianoMode, "status", "--json"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var info = JSON.parse(String(text || "{}"))
          root.pianoOn = info.enabled === true || info.pianoMode === true
          root.audioOn = info.audioConnected === true
          root.midiOn = info.midiConnected === true
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: toggleProc
    running: false
    onExited: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uEC1A"
    slotSize: Style.bar.iconSlot
    dimmed: !root.pianoOn
    keepSpace: true
    tooltipText: {
      if (!root.pianoOn) return "Piano mode"
      var bits = []
      bits.push(root.audioOn ? "AUDIO on" : "AUDIO off")
      bits.push(root.midiOn ? "MIDI on" : "MIDI off")
      return "Piano mode on — " + bits.join(", ")
    }
    onPressed: function() { root.toggle() }
  }
}
