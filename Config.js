function defaults() {
  return {
    audioName: "WU-BT10 AUDIO",
    midiName: "WU-BT10 MIDI",
    audioAddress: "",
    midiAddress: "",
    adapter: "hci0",
    setDefaultSink: true,
    sinkPriority: ["WU-BT10 AUDIO", "HDMI", "Headphones", "Speaker"]
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function parse(raw) {
  var overlay = {}
  try { overlay = JSON.parse(String(raw || "{}")) } catch (e) { overlay = {} }
  var cfg = defaults()
  if (!overlay || typeof overlay !== "object") return cfg
  var keys = Object.keys(overlay)
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    if (key === "sinkPriority" && Array.isArray(overlay[key])) {
      var list = []
      for (var j = 0; j < overlay[key].length; j++) {
        var item = String(overlay[key][j] || "").trim()
        if (item) list.push(item)
      }
      if (list.length) cfg.sinkPriority = list
    } else if (overlay[key] !== undefined) {
      cfg[key] = overlay[key]
    }
  }
  cfg.setDefaultSink = cfg.setDefaultSink === true
  return cfg
}

function stringify(cfg) {
  return JSON.stringify(cfg, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = { defaults: defaults, clone: clone, parse: parse, stringify: stringify }
}
