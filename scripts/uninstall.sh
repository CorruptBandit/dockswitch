#!/usr/bin/env bash

set -euo pipefail

BINARY_DEST="${HOME}/.local/bin/DockSwitch"
CONFIG_DEST="${HOME}/.config/dockswitch"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.dockswitch.plist"
LOG_DIR="${HOME}/Library/Logs/dockswitch"
LABEL="com.dockswitch"
REMOVE_XCODE=false

for arg in "$@"; do
    case $arg in
        --remove-xcode-tools)
            REMOVE_XCODE=true
            ;;
        *)
            echo "Unknown flag: $arg"
            echo "Usage: uninstall.sh [--remove-xcode-tools]"
            exit 1
            ;;
    esac
done

echo "==> Unloading LaunchAgent..."
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

echo "==> Removing LaunchAgent plist..."
rm -f "${PLIST_DEST}"

echo "==> Removing binary..."
rm -f "${BINARY_DEST}"

echo "==> Removing config..."
rm -rf "${CONFIG_DEST}"

echo "==> Removing logs..."
rm -rf "${LOG_DIR}"

if [[ "${REMOVE_XCODE}" == true ]]; then
    echo "==> Removing Xcode Command Line Tools..."
    sudo rm -rf /Library/Developer/CommandLineTools
    echo "    Xcode Command Line Tools removed."
fi

echo ""
echo "dockswitch uninstalled."
if [[ "${REMOVE_XCODE}" == false ]]; then
    echo "To also remove Xcode Command Line Tools re-run with the following flag: --remove-xcode-tools"
fi
