# ResX Pro (macOS)

A high-performance macOS utility built in **Swift 6** and **SwiftUI** designed for Apple Silicon (M1/M2/M3/M4) Macs to control external monitors using **DDC/CI over IOAVService**.

---

## 🌟 Key Features

### 1. Mouse-Pointer-Aware Brightness Control
- When adjusting brightness via the keyboard (**F1** / **F2** or Touch Bar / Media keys), the app automatically routes the brightness adjustment to whichever screen your mouse cursor is currently on!
- Built-in laptop display uses Apple's native `DisplayServices`.
- External monitor brightness is adjusted at the hardware level using **DDC/CI VCP Code `0x10`**, with the monitor's reported range scaled to 0–100% and read back after writes. Failed or unconfirmed requests are shown in the menu.
- The display toggle uses a reversible software blackout, leaving monitor power on. Turning it back on restores the previous visible brightness. The slider uses a 0–100% range with 1% steps.
- CLI `power-off` / `power-standby` send a real DDC power command; some monitors require their physical power button to recover.
- Displays a native macOS-style floating **HUD bezel (OSD)** on the active monitor with smooth percentage feedback.

### 2. Dynamic monitor input switching
- The user-confirmed LG 32UN650-W is recognized by its EDID vendor, product and serial IDs and shows HDMI 1, HDMI 2 and DisplayPort. Generic fallback lists no longer invent a USB-C input. A zero input readback remains unknown; no firmware or proprietary register workaround is assumed.
- The input switcher reads the external monitor's standard DDC/CI capabilities and displays the input connectors it reports.
- Input buttons highlight the confirmed selected input; gray means not selected, never disconnected or powered off. Unverified fallback ports and failed readbacks are labeled explicitly. Clicking a confirmed selected input toggles the Mac’s software blackout; other input buttons request an input switch. This does not power connected computers or consoles, and the overlay only affects the Mac’s picture.
- Buttons use generic connector names such as HDMI, DisplayPort, and USB-C. DDC/CI does not identify which device is attached to each connector, so device names are not inferred.
- **`⌥ + 2`** selects HDMI 2 and **`⌥ + 1`** selects USB-C when those inputs are available on the monitor.

### 3. External Monitor Audio Volume Control
- macOS normally disables volume keys for external monitors.
- ResX Pro controls your LG monitor speakers over DDC/CI **VCP Code `0x62`**.

### 4. Sleek Menu Bar Control Center
- Real-time indicator displaying which screen currently has the cursor.
- Independent brightness sliders for built-in and external displays.
- Volume slider for external monitor audio.
- One-click input switcher buttons with SF Symbols.

---

## 🚀 Quick Start

### Option A: Run the Menu Bar App
Launch the native menu bar agent directly:
```bash
# Run from source:
swift run

# Or build & launch the release .app bundle:
./bundle.sh
open "ResX Pro.app"
```

### Option B: Use the Terminal CLI
The app also includes a CLI for quick terminal scripts and hotkeys:
```bash
# List all displays and active DDC endpoints
swift run BetterDisplayClone list

# Check and set brightness
swift run BetterDisplayClone get-brightness
swift run BetterDisplayClone set-brightness 75

# Switch inputs
swift run BetterDisplayClone switch-ps5    # Switch to PS5 on HDMI 2
swift run BetterDisplayClone switch-hdmi2  # Switch to HDMI 2
swift run BetterDisplayClone switch-hdmi1  # Switch to HDMI 1
swift run BetterDisplayClone switch-mac    # Switch back to Mac (Type-C)
swift run BetterDisplayClone switch-dp     # Switch to DisplayPort

# Adjust volume
swift run BetterDisplayClone set-volume 50
```

---

## ⌨️ Default Keyboard Shortcuts

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| **`F1` / `F2`** | Brightness Down / Up | Adjusts brightness of the screen under the mouse pointer |
| **`⌥ + 2`** | Switch to HDMI 2 | Selects the HDMI 2 input on the external monitor |
| **`⌥ + 1`** | Switch to USB-C | Selects the USB-C input on the external monitor |

---

## 🔒 Permissions

To intercept global media keys (F1/F2) and detect cursor position across screens, macOS requires **Accessibility Permissions**:
1. When launched, click **Grant Access** in the menu bar popover (or open **System Settings → Privacy & Security → Accessibility**).
2. Enable permissions for `BetterDisplayClone`.
