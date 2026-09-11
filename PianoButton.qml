import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  property bool pianoOn: false
  property bool audioOn: false
  property bool midiOn: false

  readonly property bool audioBad: pianoOn && !audioOn
  readonly property bool midiBad: pianoOn && !midiOn
  readonly property color warnColor: (audioBad && midiBad) ? Color.urgent : "#e0b04a"

  active: pianoOn
  activeText: "\uEC1A"
  inactiveText: "\uEC1A"
  useActiveColor: false
  foreground: (audioBad || midiBad) ? warnColor : (bar ? bar.barForeground : Color.foreground)
  activeTooltipText: {
    var bits = []
    bits.push(audioOn ? "AUDIO on" : "AUDIO missing")
    bits.push(midiOn ? "MIDI on" : "MIDI missing")
    return "Piano mode on — " + bits.join(", ")
  }
  inactiveTooltipText: "Piano mode"

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
  onBarChanged: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

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
    triggeredOnStart: true
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
          if (!toggleProc.running)
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

  onPressed: function (b) {
    if (b === Qt.RightButton) {
      root.openSettings()
      return
    }
    root.toggle()
  }
}
