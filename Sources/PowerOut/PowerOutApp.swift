import SwiftUI

@main
struct PowerOutApp: App {
    @StateObject private var manager = PowerManager()

    init() {
        // Headless mode for testing: `PowerOut --activate` / `PowerOut --restore`
        let args = CommandLine.arguments
        guard args.contains("--activate") || args.contains("--restore") else { return }
        MainActor.assumeIsolated {
            let m = PowerManager()
            if args.contains("--activate") { m.activate() } else { m.restore() }
            print(m.status)
        }
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(manager)
        } label: {
            Image(systemName: manager.active ? "bolt.slash.fill" : "bolt.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var m: PowerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Button(action: m.toggle) {
                Text(m.active ? "Restore normal settings" : "Activate PowerOut")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(m.active ? .gray : .orange)

            Text(m.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("What PowerOut changes").font(.subheadline.bold())
            Toggle("Low Power Mode", isOn: $m.useLowPower)
            Toggle("Display sleep after 1 min", isOn: $m.shortenDisplaySleep)
            Toggle("Turn off Power Nap", isOn: $m.disablePowerNap)
            Toggle("Turn off Wi-Fi", isOn: $m.turnOffWiFi)
            Toggle("Turn off Bluetooth", isOn: $m.turnOffBluetooth)
            Toggle("Dark mode", isOn: $m.darkMode)
            Toggle("Dim screen", isOn: $m.dimScreen)
            if m.dimScreen {
                HStack {
                    Slider(value: $m.brightnessLevel, in: 0.05...0.6)
                    Text("\(Int(m.brightnessLevel * 100))%")
                        .monospacedDigit().frame(width: 38, alignment: .trailing)
                }
                .padding(.leading, 20)
            }

            DisclosureGroup("Quit apps (\(m.appsToQuit.count))") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(m.runningApps) { app in
                            Toggle(app.name, isOn: Binding(
                                get: { m.appsToQuit.contains(app.id) },
                                set: { on in
                                    if on { m.appsToQuit.insert(app.id) } else { m.appsToQuit.remove(app.id) }
                                }))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
            }

            Divider()

            Toggle("Auto-activate on battery below", isOn: $m.autoActivate)
            if m.autoActivate {
                Stepper("\(m.autoThreshold)%", value: $m.autoThreshold, in: 5...50, step: 5)
                    .padding(.leading, 20)
            }

            Divider()
            HStack {
                Text("PowerOut").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .frame(width: 290)
        .onAppear { m.refresh() }
    }

    private var header: some View {
        HStack {
            Image(systemName: batterySymbol)
                .font(.title2)
                .foregroundStyle(m.active ? .orange : .primary)
            VStack(alignment: .leading) {
                if let b = m.battery {
                    Text("\(b.percent)%  \(b.onBattery ? "on battery" : "plugged in")")
                        .font(.headline)
                    if let mins = b.minutesRemaining {
                        Text("\(mins / 60)h \(mins % 60)m remaining")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("No battery found").font(.headline)
                }
            }
            Spacer()
        }
    }

    private var batterySymbol: String {
        guard let b = m.battery else { return "battery.0" }
        if !b.onBattery { return "battery.100.bolt" }
        switch b.percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
