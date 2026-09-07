import QtQuick
import Quickshell
import Quickshell.Io

// Runs the WU-BT10 keep-alive while Omarchy shell is up.
Item {
  id: root

  property var manifest: null
  property var shell: null

  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string keepAlive: pluginDir + "/bin/keep-alive"
  readonly property string pianoMode: pluginDir + "/bin/piano-mode"
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string flagPath: stateHome + "/omarchy/piano-mode/enabled"

  function toggle() {
    if (pluginDir === "" || toggleProc.running) return
    toggleProc.command = [pianoMode, "toggle"]
    toggleProc.running = true
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
  }
}
