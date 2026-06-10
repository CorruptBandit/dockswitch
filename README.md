# DockSwitch

A lightweight macOS LaunchAgent written in Swift that monitors a USB device (e.g. a docking station) and automatically switches your **keyboard layout** and **scroll direction** when it is plugged in or unplugged.

## How It Works

1. DockSwitch starts at login via a LaunchAgent and reads `~/.config/dockswitch/config.json`
2. It polls the IORegistry USB plane every _n_ seconds
3. When your device connects or disconnects, it applies the configured keyboard layout and scroll direction immediately — no logout required

> **Note:** DockSwitch requires an active user session to apply keyboard and scroll settings and will not take effect until after login. This is a macOS limitation with no public API workaround.

## Requirements

- macOS Ventura or later (tested on macOS Tahoe 26.0)
- Xcode Command Line Tools (handled by the installer)
- Target keyboard layouts must be added in **System Settings → Keyboard → Input Sources** (handled by the installer)

## Building from Source

The installer builds DockSwitch from source on your machine using the Swift compiler. There are currently no pre-built binaries available.

Xcode Command Line Tools are required to compile the binary. If you do not have them installed, the installer will prompt you to install them — this is a common dependency on macOS and you may already have it if you have used Homebrew, Git, or any other developer tooling. Once the binary has been built the tools are no longer needed by DockSwitch.

To remove Xcode Command Line Tools automatically after the build, pass the `--remove-xcode-tools` flag.

## Install

    curl -fsSL https://raw.githubusercontent.com/CorruptBandit/dockswitch/main/scripts/install.sh | bash

To also remove Xcode Command Line Tools:

    curl -fsSL https://raw.githubusercontent.com/CorruptBandit/dockswitch/main/scripts/install.sh | bash -s -- --remove-xcode-tools

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

    curl -fsSL https://raw.githubusercontent.com/CorruptBandit/dockswitch/main/scripts/uninstall.sh | bash -s -- --remove-xcode-tools

## Configuration

Your config is written to `~/.config/dockswitch/config.json` during install. You can edit it at any time. Key reference:

| Key | Description |
|---|---|
| `deviceName` | Substring of your device's USB product name (case-insensitive) |
| `pollIntervalSeconds` | How often to check for device changes (minimum recommended: `1`) |
| `keyboardLayout` | Suffix of the Apple input source ID, e.g. `British-PC` to `com.apple.keylayout.British-PC` |
| `scrollDirection` | `"natural"` or `"standard"` |

> **Finding your device name:** Run `ioreg -p IOUSB` with your device plugged in. Any substring of your device name will work.

## Managing the Service

Stop the service:

    launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.dockswitch.plist

Start the service:

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
