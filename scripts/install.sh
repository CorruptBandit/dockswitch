#!/usr/bin/env bash

set -euo pipefail

REPO="https://raw.githubusercontent.com/CorruptBandit/dockswitch/main"
BINARY_DEST="${HOME}/.local/bin/DockSwitch"
CONFIG_DEST="${HOME}/.config/dockswitch/config.json"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.dockswitch.plist"
LOG_DIR="${HOME}/Library/Logs/dockswitch"
LABEL="com.dockswitch"
TMP_DIR="$(mktemp -d)"
REMOVE_XCODE=false

for arg in "$@"; do
    case $arg in
        --remove-xcode-tools)
            REMOVE_XCODE=true
            ;;
        *)
            echo "Unknown flag: $arg"
            echo "Usage: install.sh [--remove-xcode-tools]"
            exit 1
            ;;
    esac
done

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

validate_keyboard_layout() {
    local layout="${1}"
    defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleEnabledInputSources 2>/dev/null \
        | grep -qi "\"KeyboardLayout Name\" = \"*${layout}\"*"
}

validate_device_name() {
    local device="${1}"
    ioreg -p IOUSB | grep -qi "${device}@"
}

if [[ -f "${BINARY_DEST}" || -f "${PLIST_DEST}" || -f "${CONFIG_DEST}" ]]; then
    echo "An existing DockSwitch installation was detected."
    read -rp "Run uninstall first then continue? (y/n): " CONFIRM </dev/tty
    if [[ "${CONFIRM}" == "y" ]]; then
        echo "==> Uninstalling existing installation..."
        launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
        rm -f "${PLIST_DEST}"
        rm -f "${BINARY_DEST}"
        rm -rf "${HOME}/.config/dockswitch"
        rm -rf "${LOG_DIR}"
        echo "    Existing installation removed."
        echo ""
    else
        echo "Aborting. Run the uninstall script first:"
        echo "curl -fsSL ${REPO}/scripts/uninstall.sh | bash"
        exit 0
    fi
fi

if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools not found."
    echo "A macOS dialog will open in another window asking you to install them."
    echo "Click 'Install' and wait for it to complete — this may take several minutes."
    echo "This script will continue automatically once the installation is done."
    echo ""
    xcode-select --install 2>/dev/null || true
    echo "Waiting for Xcode Command Line Tools installation to complete..."
    until xcode-select -p &>/dev/null; do
        sleep 5
    done
    echo "Xcode Command Line Tools installed."
fi

echo "==> Downloading sources..."
curl -fsSL "${REPO}/src/DockSwitch.swift" -o "${TMP_DIR}/DockSwitch.swift"
curl -fsSL "${REPO}/packaging/com.dockswitch.plist.template" -o "${TMP_DIR}/com.dockswitch.plist.template"

echo "==> Building DockSwitch..."
swiftc -framework Carbon -framework Foundation -framework IOKit \
    "${TMP_DIR}/DockSwitch.swift" \
    -o "${TMP_DIR}/DockSwitch"

echo ""
echo "==> Configuring DockSwitch..."
echo "    (run 'ioreg -p IOUSB' in a new terminal to find your device name)"
echo ""

read -rp "Enter the USB device name to monitor: " DEVICE_NAME </dev/tty
while [[ -z "${DEVICE_NAME}" ]]; do
    echo "    Device name cannot be empty."
    read -rp "Enter the USB device name to monitor: " DEVICE_NAME </dev/tty
done

if ! validate_device_name "${DEVICE_NAME}"; then
    echo "    Warning: '${DEVICE_NAME}' was not found in the current USB device list."
    echo "    This is fine if your dock is not currently plugged in."
    echo "    Double check the spelling by running: ioreg -p IOUSB"
fi

read -rp "Enter keyboard layout when connected (e.g. British-PC): " LAYOUT_CONNECTED </dev/tty
while true; do
    if [[ -z "${LAYOUT_CONNECTED}" ]]; then
        echo "    Keyboard layout cannot be empty."
    elif ! validate_keyboard_layout "${LAYOUT_CONNECTED}"; then
        echo "    Layout 'com.apple.keylayout.${LAYOUT_CONNECTED}' not found."
        echo "    Either the spelling is incorrect or it has not been added yet."
        echo "    Add it via System Settings → Keyboard → Input Sources → Edit → +"
    else
        break
    fi
    read -rp "Enter keyboard layout when connected (e.g. British-PC): " LAYOUT_CONNECTED </dev/tty
done

read -rp "Enter scroll direction when connected (natural/standard): " SCROLL_CONNECTED </dev/tty
while [[ "${SCROLL_CONNECTED}" != "natural" && "${SCROLL_CONNECTED}" != "standard" ]]; do
    echo "    Must be 'natural' or 'standard'."
    read -rp "Enter scroll direction when connected (natural/standard): " SCROLL_CONNECTED </dev/tty
done

read -rp "Enter keyboard layout when disconnected (e.g. British): " LAYOUT_DISCONNECTED </dev/tty
while true; do
    if [[ -z "${LAYOUT_DISCONNECTED}" ]]; then
        echo "    Keyboard layout cannot be empty."
    elif ! validate_keyboard_layout "${LAYOUT_DISCONNECTED}"; then
        echo "    Layout 'com.apple.keylayout.${LAYOUT_DISCONNECTED}' not found."
        echo "    Either the spelling is incorrect or it has not been added yet."
        echo "    Add it via System Settings → Keyboard → Input Sources → Edit → +"
    else
        break
    fi
    read -rp "Enter keyboard layout when disconnected (e.g. British): " LAYOUT_DISCONNECTED </dev/tty
done

read -rp "Enter scroll direction when disconnected (natural/standard): " SCROLL_DISCONNECTED </dev/tty
while [[ "${SCROLL_DISCONNECTED}" != "natural" && "${SCROLL_DISCONNECTED}" != "standard" ]]; do
    echo "    Must be 'natural' or 'standard'."
    read -rp "Enter scroll direction when disconnected (natural/standard): " SCROLL_DISCONNECTED </dev/tty
done

read -rp "Enter poll interval in seconds (default: 3): " POLL_INTERVAL </dev/tty
POLL_INTERVAL="${POLL_INTERVAL:-3}"
while ! [[ "${POLL_INTERVAL}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "${POLL_INTERVAL} < 1" | bc -l) )); do
    echo "    Poll interval must be a number >= 1."
    read -rp "Enter poll interval in seconds (default: 3): " POLL_INTERVAL </dev/tty
    POLL_INTERVAL="${POLL_INTERVAL:-3}"
done

echo ""
echo "==> Creating directories..."
mkdir -p "${HOME}/.local/bin"
mkdir -p "${HOME}/.config/dockswitch"
mkdir -p "${LOG_DIR}"
mkdir -p "${HOME}/Library/LaunchAgents"

echo "==> Installing binary..."
cp "${TMP_DIR}/DockSwitch" "${BINARY_DEST}"
chmod 755 "${BINARY_DEST}"

echo "==> Writing config..."
cat > "${CONFIG_DEST}" <<EOF
{
    "deviceName": "${DEVICE_NAME}",
    "pollIntervalSeconds": ${POLL_INTERVAL},
    "onConnected": {
        "keyboardLayout": "${LAYOUT_CONNECTED}",
        "scrollDirection": "${SCROLL_CONNECTED}"
    },
    "onDisconnected": {
        "keyboardLayout": "${LAYOUT_DISCONNECTED}",
        "scrollDirection": "${SCROLL_DISCONNECTED}"
    }
}
EOF

echo "==> Installing LaunchAgent..."
sed "s|__HOME__|${HOME}|g" "${TMP_DIR}/com.dockswitch.plist.template" > "${PLIST_DEST}"

echo "==> Loading LaunchAgent..."
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_DEST}"

if [[ "${REMOVE_XCODE}" == true ]]; then
    echo "==> Removing Xcode Command Line Tools..."
    sudo rm -rf /Library/Developer/CommandLineTools
    echo "    Xcode Command Line Tools removed."
fi

echo ""
echo "dockswitch installed and running."
echo "Edit config : ${CONFIG_DEST}"
echo "View logs   : tail -f ${LOG_DIR}/stdout.log"
