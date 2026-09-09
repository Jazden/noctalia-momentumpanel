# Sennheiser Momentum for Noctalia Shell (`noctalia-momentumpanel`)

A native desktop control panel and top-bar widget for **Sennheiser Momentum** headphones (Momentum 4, Momentum 3, Accentum, etc.) on Linux with **Noctalia**.

Engineered to integrate seamlessly with the ultra-lightweight [`momentumd`](https://github.com/Jazden/momentumd) daemon via Unix domain sockets for zero-latency (<5ms) adjustments, negligible CPU utilization, and real-time battery status.

---

## Features

* **Top-Bar Widget**:
  * Dynamic noise cancellation glyph (`shield-check` for ANC, `ear` for Transparency, `headphones` for Off).
  * Real-time headphone battery percentage.
  * Informative tooltips displaying connected device name, active noise mode, battery percentage, and Bass Boost status.
  * **Left-Click**: Toggles the popup control panel.
  * **Right-Click**: Cycles noise cancellation modes (`ANC` → `Transparency` → `Off`).

* **Floating Control Panel**:
  * Centered over-ear battery meter and connection badge.
  * One-tap mode buttons for **Active Noise Cancellation (ANC)**, **Transparency**, and **Off**.
  * **Continuous Transparency Level Slider** (0% to 100%) for fine-tuning ambient awareness.
  * **Settings Accordion**:
    * **Bass Boost**: Toggle deep, dynamic low-end punch.
    * **Smart Pause**: Real-time status for wear detection.
    * **Sidetone**: Status indicator for call monitoring.
  * **Disconnected Guidance**: Clean state presentation with a one-click **"Connect Headphones"** button.

* **IPC & Keybinding Integration**:
  * Supports hotkey triggers and window manager keybindings through `noctalia msg`:
    ```bash
    # Toggle control panel
    noctalia msg panel-toggle jazden/momentum:panel

    # Cycle noise modes
    noctalia msg plugin jazden/momentum:service all cycle-noise

    # Toggle Bass Boost
    noctalia msg plugin jazden/momentum:service all toggle-bass
    ```

---

## Prerequisites

1. **Linux Bluetooth**: `bluez` installed and running.
2. **Python 3**: For plugin IPC script execution.
3. **`momentumd` Daemon**:
   Install and start [`momentumd`](https://github.com/Jazden/momentumd):
   ```bash
   git clone https://github.com/Jazden/momentumd.git
   cd momentumd
   cargo build --release
   cp target/release/momentumd ~/.cargo/bin/
   mkdir -p ~/.config/systemd/user
   cp momentumd.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now momentumd
   ```

---

## Installation

Symlink the plugin directory into your Noctalia plugins folder:

```bash
mkdir -p ~/.local/share/noctalia/plugins
ln -s "$(pwd)/plugin" ~/.local/share/noctalia/plugins/momentum
```

Enable the plugin in Noctalia:

```bash
noctalia msg plugins enable jazden/momentum
```

To add the widget to your bar, open your Noctalia configuration (`~/.config/noctalia/config.json`) and add `"jazden/momentum:momentum"` to your desired bar section.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
