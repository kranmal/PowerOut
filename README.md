# PowerOut

A tiny macOS menu bar app that makes your MacBook battery last as long as possible when you can't plug in, for example during a power cut.

One click turns off or dials down everything that quietly drains power. One more click puts it all back exactly as it was.

![platform](https://img.shields.io/badge/macOS-13%2B-blue) ![swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![license](https://img.shields.io/badge/license-MIT-green)

## What it does

Click the bolt icon in the menu bar to see your battery level and time remaining, then press **Activate PowerOut**. You choose which of these it applies:

| Setting | What changes |
|---|---|
| Low Power Mode | Throttles CPU and background activity |
| Display sleep | Screen sleeps after 1 minute idle |
| Power Nap | Stops the Mac waking up to fetch mail and updates while asleep |
| Wi-Fi | Turned off |
| Bluetooth | Turned off |
| Dark mode | Switched on (saves a little on LCD, more on OLED) |
| Screen brightness | Dimmed to a level you pick (default 25%) |
| Apps | Any running apps you tick are asked to quit |

Press **Restore normal settings** and everything goes back to what it was before. PowerOut saves a snapshot first, and it survives quitting or relaunching the app.

**Auto-activate:** optionally switch itself on once when your battery drops below a threshold (5 to 50%) while unplugged.

### Things it deliberately does not do
- It only changes your **battery** power profile, never your plugged-in (AC) one.
- It quits apps politely (the same as Cmd+Q), never force-kills them. Nothing is selected by default.
- It does not relaunch apps it quit when you restore.
- It collects no data and makes no network connections.

## Install

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```bash
git clone https://github.com/kranmal/PowerOut.git
cd PowerOut
./build.sh
open build/PowerOut.app
```

To keep it, drag `build/PowerOut.app` into `/Applications`.

The app is ad-hoc signed, not notarized. If macOS refuses to open it the first time, right-click the app and choose **Open**.

### Permissions you will be asked for
- **Administrator password:** to change Low Power Mode, display sleep and Power Nap (`pmset` needs root). You get one prompt per Activate and one per Restore.
- **Bluetooth:** to read and switch Bluetooth power.
- **Automation (System Events):** to switch dark mode.

Skip any setting by unticking it. Nothing is asked for if you don't use it.

## How it works

PowerOut is a SwiftUI `MenuBarExtra` app with no Dock icon (`LSUIElement`). There are two source files that matter:

- `PowerManager.swift` holds the logic. On **Activate** it first records the current state in a `Snapshot` (Low Power Mode, display sleep, Power Nap, Wi-Fi, Bluetooth, brightness, dark mode) and saves it to `UserDefaults`. It then applies your chosen settings and sets `active = true`. On **Restore** it reads the snapshot back and reverses each change.
- `System.swift` has one small wrapper per setting:

| Setting | Mechanism |
|---|---|
| Low Power Mode, display sleep, Power Nap | `pmset -b ...`, run through `osascript` with administrator privileges, batched into one prompt |
| Wi-Fi | `networksetup -setairportpower` |
| Bluetooth | `IOBluetoothPreference{Get,Set}ControllerPowerState` (private API) |
| Brightness | `DisplayServicesGet/SetBrightness` (private API) |
| Dark mode | AppleScript via System Events |
| Battery level and time left | IOKit `IOPSCopyPowerSourcesInfo` |

`build.sh` runs `swift build -c release`, wraps the binary in a `.app` bundle with an `Info.plist`, and ad-hoc signs it. There is no Xcode project.

### Caveats
- Bluetooth and brightness use **private Apple APIs**. A future macOS update could break them. If one stops working, the rest still do.
- Turning off Bluetooth disconnects Bluetooth keyboards and mice, so keep a wired or built-in option available.
- Dimming the screen only works on displays that expose brightness control (built-in MacBook displays do).

## Testing without the UI

The same code can run headlessly, which is how it was tested:

```bash
open -n -W build/PowerOut.app --args --activate
open -n -W build/PowerOut.app --args --restore
```

Launch it with `open`. Running the binary directly from a shell crashes when it touches Bluetooth, because macOS attributes the privacy request to the parent process.

## Tips for a long outage

PowerOut handles the settings. For the rest, close heavy apps, keep the lid shut when you're not using it, and charge from a USB-C Power Delivery power bank if you have one. Only charge when you must: a lithium battery is happiest between about 20% and 80%.

## License

MIT, see [LICENSE](LICENSE).
