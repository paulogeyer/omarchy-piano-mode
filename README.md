# Piano Mode

Omarchy shell plugin for **Casio digital pianos** that use the **WU-BT10**
Bluetooth dongle.

Plugin id: `casio.wu-bt10-piano`

![Piano-mode icon on the status bar](images/status-bar.png)

One bar button turns **piano mode** on or off. While it is on, the plugin
keeps both WU-BT10 radios connected:

| Device | Bluetooth | Role |
|---|---|---|
| **WU-BT10 AUDIO** | Classic A2DP | Piano speakers / audio out |
| **WU-BT10 MIDI** | BLE MIDI | Keys, metronome, SysEx (MUSIC SPACE protocol) |

Those are two different Bluetooth addresses on the same dongle. MIDI is
unpaired LE (`AddressType=random`) and must stay Trusted while it is visible,
or BlueZ drops it. The keep-alive holds an LE scan on its own D-Bus connection
until MIDI is up.

It does **not** manage other Bluetooth audio (headphones, speakers). Piano
mode is independent of those.

Devices are found by BlueZ name (`WU-BT10 AUDIO`, `WU-BT10 MIDI`). Optional
MAC overrides go in `~/.config/omarchy/piano-mode.json`.

## Install

```sh
omarchy plugin add https://github.com/paulogeyer/omarchy-piano-mode.git --enable
```

From a local checkout:

```sh
omarchy plugin add "$HOME/Projects/piano_mode" --enable --yes
```

The shell loads `~/.config/omarchy/plugins/casio.wu-bt10-piano` (a git clone).
Do not symlink that path.

Click the piano icon on the bar, or:

```sh
~/.config/omarchy/plugins/casio.wu-bt10-piano/bin/piano-mode toggle
omarchy-shell casio.wu-bt10-piano toggle
```

Close **MUSIC SPACE** on the phone while MIDI is in use; it holds BLE MIDI
exclusively.

## Config

`~/.config/omarchy/piano-mode.json` overlays `defaults.json`:

```json
{
  "audioName": "WU-BT10 AUDIO",
  "midiName": "WU-BT10 MIDI",
  "audioAddress": "",
  "midiAddress": "",
  "adapter": "hci0",
  "setDefaultSink": true,
  "sinkPriority": ["WU-BT10 AUDIO"]
}
```

Empty addresses mean “match by name”. Set MACs if several WU-BT10 dongles
are in range.

When piano mode is on, the plugin sets the default PipeWire output from the
**Bluetooth audio** devices in this list. Drag rows to set the order; the
first connected device wins. **WU-BT10 AUDIO** is first by default. Turning
piano mode off restores the previous output.

Right-click the piano icon (or run `omarchy-shell casio.wu-bt10-piano settings`)
to toggle this and drag devices into order.

## Files

- `bin/piano-mode` — `on` / `off` / `toggle` / `status`
- `bin/keep-alive` — reconnect AUDIO + MIDI while piano mode is on
- `Service.qml` — runs keep-alive with the shell, output-priority settings
- `PianoButton.qml` — bar toggle (right-click for output settings)
- `images/status-bar.png` — piano-mode icon on the bar

## License

MIT. See [LICENSE](LICENSE).
