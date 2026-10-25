import Foundation
import AppKit
import SwiftUI

/// What the machine looked like before PowerOut touched it, so it can be put back.
struct Snapshot: Codable {
    var lowPowerMode: Int?
    var displaySleep: Int?
    var powerNap: Int?
    var wifiOn: Bool
    var bluetoothOn: Bool
    var brightness: Float?
    var darkMode: Bool
}

struct RunningApp: Identifiable, Hashable {
    let id: String   // bundle identifier
    let name: String
}

@MainActor
final class PowerManager: ObservableObject {
    private let defaults = UserDefaults.standard
    private let snapshotKey = "PowerOut.snapshot"

    @Published var active: Bool
    @Published var status: String = "Ready"
    @Published var battery: BatteryInfo?
    @Published var runningApps: [RunningApp] = []

    // Which actions to apply
    @Published var useLowPower: Bool { didSet { save("useLowPower", useLowPower) } }
    @Published var shortenDisplaySleep: Bool { didSet { save("shortenDisplaySleep", shortenDisplaySleep) } }
    @Published var disablePowerNap: Bool { didSet { save("disablePowerNap", disablePowerNap) } }
    @Published var turnOffWiFi: Bool { didSet { save("turnOffWiFi", turnOffWiFi) } }
    @Published var turnOffBluetooth: Bool { didSet { save("turnOffBluetooth", turnOffBluetooth) } }
    @Published var dimScreen: Bool { didSet { save("dimScreen", dimScreen) } }
    @Published var darkMode: Bool { didSet { save("darkMode", darkMode) } }
    @Published var brightnessLevel: Double { didSet { defaults.set(brightnessLevel, forKey: "brightnessLevel") } }
    @Published var autoActivate: Bool { didSet { save("autoActivate", autoActivate) } }
    @Published var autoThreshold: Int { didSet { defaults.set(autoThreshold, forKey: "autoThreshold") } }
    @Published var appsToQuit: Set<String> {
        didSet { defaults.set(Array(appsToQuit), forKey: "appsToQuit") }
    }

    private var autoSuppressed = false
    private var timer: Timer?

    init() {
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
        }
        active = UserDefaults.standard.data(forKey: "PowerOut.snapshot") != nil
        useLowPower = flag("useLowPower", true)
        shortenDisplaySleep = flag("shortenDisplaySleep", true)
        disablePowerNap = flag("disablePowerNap", true)
        turnOffWiFi = flag("turnOffWiFi", true)
        turnOffBluetooth = flag("turnOffBluetooth", true)
        dimScreen = flag("dimScreen", true)
        darkMode = flag("darkMode", true)
        brightnessLevel = UserDefaults.standard.object(forKey: "brightnessLevel") as? Double ?? 0.25
        autoActivate = flag("autoActivate", false)
        autoThreshold = UserDefaults.standard.object(forKey: "autoThreshold") as? Int ?? 20
        appsToQuit = Set(UserDefaults.standard.stringArray(forKey: "appsToQuit") ?? [])

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func save(_ key: String, _ value: Bool) { defaults.set(value, forKey: key) }

    // MARK: Refresh

    func refresh() {
        battery = readBattery()
        let me = Bundle.main.bundleIdentifier
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != me, id != "com.apple.finder",
                      let name = app.localizedName else { return nil }
                return RunningApp(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func tick() {
        refresh()
        guard let b = battery else { return }
        if !b.onBattery { autoSuppressed = false }
        if autoActivate, !active, !autoSuppressed, b.onBattery, b.percent <= autoThreshold {
            autoSuppressed = true   // one attempt per discharge cycle
            activate()
        }
    }

    // MARK: Activate / restore

    func toggle() { active ? restore() : activate() }

    func activate() {
        guard !active else { return }
        let snap = Snapshot(
            lowPowerMode: Pmset.batteryValue("lowpowermode"),
            displaySleep: Pmset.batteryValue("displaysleep"),
            powerNap: Pmset.batteryValue("powernap"),
            wifiOn: WiFi.isOn,
            bluetoothOn: Bluetooth.isOn,
            brightness: Brightness.current,
            darkMode: Appearance.isDark)

        var done: [String] = []

        // Privileged settings, one admin prompt for all of them (battery profile only).
        var cmds: [String] = []
        if useLowPower { cmds.append("/usr/bin/pmset -b lowpowermode 1") }
        if shortenDisplaySleep { cmds.append("/usr/bin/pmset -b displaysleep 1") }
        if disablePowerNap { cmds.append("/usr/bin/pmset -b powernap 0") }
        if !cmds.isEmpty {
            if runAsAdmin(cmds.joined(separator: "; ")) {
                done.append("power settings")
            } else {
                status = "Cancelled: admin approval is needed for power settings"
                return
            }
        }

        if turnOffWiFi { WiFi.set(false); done.append("Wi-Fi") }
        if turnOffBluetooth { Bluetooth.set(false); done.append("Bluetooth") }
        if dimScreen { Brightness.set(Float(brightnessLevel)); done.append("brightness") }
        if darkMode && !snap.darkMode { Appearance.setDark(true); done.append("dark mode") }

        var quit = 0
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, appsToQuit.contains(id) {
                app.terminate()
                quit += 1
            }
        }
        if quit > 0 { done.append("\(quit) app\(quit == 1 ? "" : "s") quit") }

        if let data = try? JSONEncoder().encode(snap) { defaults.set(data, forKey: snapshotKey) }
        active = true
        status = "On: " + (done.isEmpty ? "nothing selected" : done.joined(separator: ", "))
        refresh()
    }

    func restore() {
        guard let data = defaults.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            active = false
            status = "Nothing to restore"
            return
        }

        var cmds: [String] = []
        if useLowPower, let v = snap.lowPowerMode { cmds.append("/usr/bin/pmset -b lowpowermode \(v)") }
        if shortenDisplaySleep, let v = snap.displaySleep { cmds.append("/usr/bin/pmset -b displaysleep \(v)") }
        if disablePowerNap, let v = snap.powerNap { cmds.append("/usr/bin/pmset -b powernap \(v)") }
        if !cmds.isEmpty && !runAsAdmin(cmds.joined(separator: "; ")) {
            status = "Cancelled: admin approval is needed to restore power settings"
            return
        }

        if turnOffWiFi && snap.wifiOn { WiFi.set(true) }
        if turnOffBluetooth && snap.bluetoothOn { Bluetooth.set(true) }
        if dimScreen, let b = snap.brightness { Brightness.set(b) }
        if darkMode && !snap.darkMode { Appearance.setDark(false) }

        defaults.removeObject(forKey: snapshotKey)
        active = false
        status = "Settings restored"
        refresh()
    }
}
