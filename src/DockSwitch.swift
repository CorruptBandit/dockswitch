import Carbon
import Foundation
import IOKit
import IOKit.usb

// MARK: - Configuration Model

struct DeviceAction: Decodable {
    let keyboardLayout: String
    let scrollDirection: ScrollDirection
}

enum ScrollDirection: String, Decodable {
    case natural
    case standard

    var boolValue: Bool {
        switch self {
        case .natural:  return true
        case .standard: return false
        }
    }
}

struct Configuration: Decodable {
    let deviceName: String
    let pollIntervalSeconds: TimeInterval
    let onConnected: DeviceAction
    let onDisconnected: DeviceAction
}

// MARK: - Config Errors

enum ConfigError: LocalizedError {
    case fileNotFound(String)
    case missingKey(String)
    case malformedJSON(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Config file not found at '\(path)'."
        case .missingKey(let key):
            return "Config is missing required key: '\(key)'."
        case .malformedJSON(let underlying):
            return "Failed to parse config JSON: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Logger

enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func info(_ message: String) {
        print("[\(formatter.string(from: Date()))] [INFO]  \(message)")
        fflush(stdout)
    }

    static func error(_ message: String) {
        fputs("[\(formatter.string(from: Date()))] [ERROR] \(message)\n", stderr)
    }
}

// MARK: - Configuration Loading

func loadConfiguration(at path: String) throws -> Configuration {
    guard FileManager.default.fileExists(atPath: path) else {
        throw ConfigError.fileNotFound(path)
    }

    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)

    do {
        return try JSONDecoder().decode(Configuration.self, from: data)
    } catch let decodingError as DecodingError {
        switch decodingError {
        case .keyNotFound(let key, _):
            throw ConfigError.missingKey(key.stringValue)
        default:
            throw ConfigError.malformedJSON(underlying: decodingError)
        }
    }
}

// MARK: - USB Device Detection

/// Queries the IORegistry USB plane for a device whose product name
/// case-insensitively contains `deviceName`.
func isDeviceConnected(_ deviceName: String) -> Bool {
    guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else {
        Log.error("Failed to create IOService matching dictionary.")
        return false
    }

    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
    guard result == KERN_SUCCESS else {
        Log.error("IOServiceGetMatchingServices failed with code \(result).")
        return false
    }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != 0 {
        defer {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        if let cfName = IORegistryEntryCreateCFProperty(
            service,
            "USB Product Name" as CFString,
            kCFAllocatorDefault,
            0
        ) {
            if let name = cfName.takeRetainedValue() as? String,
               name.localizedCaseInsensitiveContains(deviceName)
            {
                return true
            }
        }
    }

    return false
}

// MARK: - Keyboard Layout Switching

/// Selects the given keyboard input source.
/// The layout must already be added in System Settings → Keyboard → Input Sources.
func switchKeyboardLayout(to layout: String) {
    let sourceID = "com.apple.keylayout.\(layout)"

    guard let sourceList = TISCreateInputSourceList(
        [kTISPropertyInputSourceID: sourceID] as CFDictionary,
        false
    )?.takeRetainedValue() as? [TISInputSource],
          let source = sourceList.first
    else {
        Log.error(
            "Keyboard layout '\(sourceID)' not found. "
            + "Ensure it is added in System Settings → Keyboard → Input Sources."
        )
        return
    }

    let status = TISSelectInputSource(source)
    if status == noErr {
        Log.info("Keyboard layout → \(layout)")
    } else {
        Log.error("TISSelectInputSource failed for '\(layout)' (OSStatus \(status)).")
    }
}

// MARK: - Scroll Direction Switching

private let activateSettingsPath =
    "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

private let scrollDirectionKey = "com.apple.swipescrolldirection" as CFString
private let globalDomain      = kCFPreferencesAnyApplication
private let currentUser       = kCFPreferencesCurrentUser
private let currentHost       = kCFPreferencesCurrentHost

/// Writes the scroll direction via CFPreferences (equivalent to `defaults write -g`)
/// and activates the change without requiring a logout.
/// No public Swift/Cocoa API exists for either the preference domain or activation;
/// CFPreferences is the lowest-level public API available.
func switchScrollDirection(to direction: ScrollDirection) {
    // 1. Write via CFPreferences
    CFPreferencesSetValue(
        scrollDirectionKey,
        direction.boolValue as CFBoolean,
        globalDomain,
        currentUser,
        currentHost
    )

    guard CFPreferencesSynchronize(globalDomain, currentUser, currentHost) else {
        Log.error("CFPreferencesSynchronize failed for scroll direction.")
        return
    }

    // 2. Verify the write took effect
    guard let stored = CFPreferencesCopyAppValue(scrollDirectionKey, globalDomain) as? Bool,
          stored == direction.boolValue
    else {
        Log.error("Scroll direction verification failed after write.")
        return
    }

    // 3. Activate without requiring logout
    guard FileManager.default.isExecutableFile(atPath: activateSettingsPath) else {
        Log.error(
            "activateSettings not found at \(activateSettingsPath). "
            + "Settings written but may not apply until logout."
        )
        return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: activateSettingsPath)
    process.arguments = ["-u"]

    do {
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            Log.error("activateSettings exited with status \(process.terminationStatus).")
            return
        }

        Log.info("Scroll direction → \(direction.rawValue)")
    } catch {
        Log.error("Failed to launch activateSettings: \(error.localizedDescription)")
    }
}

// MARK: - Apply Action

func applyAction(_ action: DeviceAction) {
    switchKeyboardLayout(to: action.keyboardLayout)
    switchScrollDirection(to: action.scrollDirection)
}

// MARK: - Signal Handling

func installSignalHandlers() {
    let handler: @convention(c) (Int32) -> Void = { sig in
        let name = sig == SIGTERM ? "SIGTERM" : "SIGINT"
        Log.info("Received \(name). Shutting down.")
        exit(0)
    }
    signal(SIGTERM, handler)
    signal(SIGINT, handler)
}

// MARK: - Entry Point

func main() {
    let configPath: String
    if CommandLine.arguments.count > 1 {
        configPath = CommandLine.arguments[1]
    } else {
        let binaryDir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
        configPath = (binaryDir as NSString).appendingPathComponent("config.json")
    }

    Log.info("Dock Switch starting")
    Log.info("Config: \(configPath)")

    let config: Configuration
    do {
        config = try loadConfiguration(at: configPath)
    } catch {
        Log.error("\(error.localizedDescription)")
        Log.error("Exiting. Fix the config file and restart the service.")
        exit(1)
    }

    Log.info("Monitoring device: \"\(config.deviceName)\"")
    Log.info("Poll interval: \(config.pollIntervalSeconds)s")

    installSignalHandlers()

    var wasConnected = isDeviceConnected(config.deviceName)
    Log.info("Initial state: \(wasConnected ? "connected" : "disconnected")")
    applyAction(wasConnected ? config.onConnected : config.onDisconnected)

    while true {
        Thread.sleep(forTimeInterval: config.pollIntervalSeconds)

        let isConnected = isDeviceConnected(config.deviceName)
        guard isConnected != wasConnected else { continue }

        wasConnected = isConnected
        if isConnected {
            Log.info("Device '\(config.deviceName)' connected.")
            applyAction(config.onConnected)
        } else {
            Log.info("Device '\(config.deviceName)' disconnected.")
            applyAction(config.onDisconnected)
        }
    }
}

main()
