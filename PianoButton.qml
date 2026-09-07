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
  property bool audioExpected: false

  readonly property bool audioBad: pianoOn && !audioOn
  readonly property bool midiBad: pianoOn && !midiOn
  readonly property color warnColor: (audioBad && midiBad) ? Color.urgent : "#e0b04a"

  readonly property string pluginDir: {
    var home = Quickshell.env("HOME") || ""
    var configHome = Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
    return configHome + "/omarchy/plugins/casio.wu-bt10-piano"
  }
  readonly property string pianoMode: pluginDir + "/bin/piano-mode"
  readonly property string flagPath: {
    var home = Quickshell.env("HOME") || ""
    var stateHome = Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
    return stateHome + "/omarchy/piano-mode/enabled"
  }

  implicitWidth: vertical ? barSize : Style.bar.iconSlot
  implicitHeight: vertical ? Style.bar.iconSlot : barSize

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (toggleProc.running) return
    if (root.pianoOn) {
      root.pianoOn = false
      toggleProc.command = [pianoMode, "off"]
    } else {
      root.pianoOn = true
      toggleProc.command = [pianoMode, "on"]
    }
    toggleProc.running = true
  }

  function openSettings() {
    var svc = root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
      ? root.bar.shell.serviceFor("casio.wu-bt10-piano")
      : null
    if (svc && typeof svc.openSettings === "function")
      svc.openSettings()
    else
      Quickshell.execDetached(["omarchy-shell", "casio.wu-bt10-piano", "settings"])
  }

  Component.onCompleted: refresh()

  FileView {
    path: root.flagPath
    watchChanges: true
    printErrors: false
    onLoaded: if (!toggleProc.running) root.pianoOn = true
    onLoadFailed: root.pianoOn = false
  }

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
          root.audioOn = info.audioConnected === true
          root.midiOn = info.midiConnected === true
          root.audioExpected = info.audioExpected === true
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
    useActiveColor: false
    foreground: (root.audioBad || root.midiBad)
                ? root.warnColor
                : (root.bar ? root.bar.barForeground : Color.foreground)
    keepSpace: true
    tooltipText: {
      if (!root.pianoOn) return "Piano mode"
      var bits = []
      bits.push(root.audioOn ? "AUDIO on" : "AUDIO missing")
      bits.push(root.midiOn ? "MIDI on" : "MIDI missing")
      return "Piano mode on — " + bits.join(", ")
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openSettings()
      else root.toggle()
    }
  }
}
