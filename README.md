# DockSwitch

A lightweight macOS LaunchAgent written in Swift that monitors a USB device (e.g. a docking station) and automatically switches your **keyboard layout** and **scroll direction** when it is plugged in or unplugged.

## How It Works

1. DockSwitch starts at login via a LaunchAgent and reads `~/.config/dockswitch/config.json`
2. It polls the IORegistry USB plane every _n_ seconds
3. When your device connects or disconnects, it applies the configured keyboard layout and scroll direction immediately — no logout required

## Requirements

- macOS Ventura or later
- Xcode Command Line Tools (installer script will handle this)
- Target keyboard layouts must be pre-added in **System Settings → Keyboard → Input Sources**

## Install

    curl -fsSL https://raw.githubusercontent.com/CorruptBandit/dockswitch/main/scripts/install.sh | bash

The installer will:

- Build the binary from source on your machine
- Prompt you to configure your device settings
- Install the binary to `~/.local/bin/`
- Write your config to `~/.config/dockswitch/config.json`
- Register and start the LaunchAgent

### Example

    ==> Configuring DockSwitch...
        (run 'ioreg -p IOUSB' in a new terminal to find your device name)

    Enter the USB device name to monitor: TBT4 KVM HUB
    Enter keyboard layout when connected (e.g. British-PC): British-PC
    Enter scroll direction when connected (natural/standard): standard
    Enter keyboard layout when disconnected (e.g. British): British
    Enter scroll direction when disconnected (natural/standard): natural
    Enter poll interval in seconds (default: 3): 3

## Uninstall

    curl -fsSL https://raw.githubusercontent.com/CorruptBandit/dockswitch/main/scripts/uninstall.sh | bash

To also remove Xcode Command Line Tools:

    curl -fsSL https://raw.githubusercontent.com/CorruptBandit/dockswitch/main/scripts/uninstall.sh | bash -s -- --xcode-tools

## Configuration

Your config is written to `~/.config/dockswitch/config.json` during install. You can edit it at any time. See [`config.json`](config.json) for a full example. Key reference:

| Key | Description |
|---|---|
| `deviceName` | Substring of your device's USB product name (case-insensitive) |
| `pollIntervalSeconds` | How often to check for device changes (minimum recommended: `1`) |
| `keyboardLayout` | Suffix of the Apple input source ID, e.g. `British-PC` → `com.apple.keylayout.British-PC` |
| `scrollDirection` | `"natural"` or `"standard"` |

> **Finding your device name:** Run `ioreg -p IOUSB` with your device plugged in and look for the `"USB Product Name"` field. Any substring of that value will work.

## Managing the Service

    launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.dockswitch.plist
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dockswitch.plist

View logs:

    tail -f ~/Library/Logs/dockswitch/stdout.log
    tail -f ~/Library/Logs/dockswitch/stderr.log

## Keyboard Layouts

The `keyboardLayout` value maps to `com.apple.keylayout.<value>`. Common values:

| Layout | Value |
|---|---|
| British | `British` |
| British PC | `British-PC` |
| US | `ABC` |
| US Extended | `USExtended` |

The full list of enabled layouts can be found by running:

    defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources

## License

MIT — see [`LICENSE`](LICENSE)
