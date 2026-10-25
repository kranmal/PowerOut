import Foundation
import AppKit
import CoreGraphics
import IOKit.ps

// MARK: - Shell helpers

struct ShellResult {
    let status: Int32
    let output: String
}

@discardableResult
func sh(_ path: String, _ args: [String]) -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return ShellResult(status: -1, output: "") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return ShellResult(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

/// Runs a shell script as root via the standard macOS admin password prompt.
func runAsAdmin(_ script: String) -> Bool {
    let escaped = script
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let r = sh("/usr/bin/osascript",
               ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    return r.status == 0
}

// MARK: - pmset (battery profile)

enum Pmset {
    /// Reads a value from the "Battery Power" section of `pmset -g custom`.
    static func batteryValue(_ key: String) -> Int? {
        let text = sh("/usr/bin/pmset", ["-g", "custom"]).output
        var inBattery = false
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("Power:") { inBattery = trimmed.hasPrefix("Battery") ; continue }
            guard inBattery else { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == key { return Int(parts[1]) }
        }
        return nil
    }
}

// MARK: - Wi-Fi

enum WiFi {
    static let device: String = {
        let text = sh("/usr/sbin/networksetup", ["-listallhardwareports"]).output
        let lines = text.components(separatedBy: "\n")
        for (i, l) in lines.enumerated() where l.contains("Hardware Port: Wi-Fi") {
            if i + 1 < lines.count, let r = lines[i + 1].range(of: "Device: ") {
                return String(lines[i + 1][r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return "en0"
    }()

    static var isOn: Bool {
        sh("/usr/sbin/networksetup", ["-getairportpower", device]).output.contains(": On")
    }

    static func set(_ on: Bool) {
        sh("/usr/sbin/networksetup", ["-setairportpower", device, on ? "on" : "off"])
    }
}

// MARK: - Bluetooth (private IOBluetooth symbols)

@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
private func IOBluetoothPreferenceGetControllerPowerState() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
private func IOBluetoothPreferenceSetControllerPowerState(_ state: Int32)

enum Bluetooth {
    static var isOn: Bool { IOBluetoothPreferenceGetControllerPowerState() != 0 }
    static func set(_ on: Bool) { IOBluetoothPreferenceSetControllerPowerState(on ? 1 : 0) }
}

// MARK: - Display brightness (private DisplayServices)

enum Brightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static var current: Float? {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        let fn = unsafeBitCast(sym, to: GetFn.self)
        var value: Float = 0
        return fn(CGMainDisplayID(), &value) == 0 ? value : nil
    }

    static func set(_ value: Float) {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return }
        let fn = unsafeBitCast(sym, to: SetFn.self)
        _ = fn(CGMainDisplayID(), max(0, min(1, value)))
    }
}

// MARK: - Dark mode

enum Appearance {
    static var isDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func setDark(_ dark: Bool) {
        sh("/usr/bin/osascript", ["-e",
            "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"])
    }
}

// MARK: - Battery

struct BatteryInfo {
    let percent: Int
    let onBattery: Bool
    let minutesRemaining: Int?
}

func readBattery() -> BatteryInfo? {
    guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCap = max(d[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
        let onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
        let t = d[kIOPSTimeToEmptyKey] as? Int
        return BatteryInfo(percent: cur * 100 / maxCap, onBattery: onBattery,
                           minutesRemaining: (t ?? -1) > 0 ? t : nil)
    }
    return nil
}
