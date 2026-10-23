# BetterDisplay Pro Clone (macOS)

A high-performance macOS utility built in **Swift 6** and **SwiftUI** designed for Apple Silicon (M1/M2/M3/M4) Macs to control external monitors using **DDC/CI over IOAVService**.

---

## 🌟 Key Features

### 1. Mouse-Pointer-Aware Brightness Control
- When adjusting brightness via the keyboard (**F1** / **F2** or Touch Bar / Media keys), the app automatically routes the brightness adjustment to whichever screen your mouse cursor is currently on!
- Built-in laptop display uses Apple's native `DisplayServices`.
- External LG monitor is adjusted at the hardware level using **DDC/CI VCP Code `0x10`**.
- Displays a native macOS-style floating **HUD bezel (OSD)** on the active monitor with smooth percentage feedback.

### 2. Instant Input Port Switching (PS5 🎮 & Mac 💻)
- Seamlessly switch your LG monitor's input source without touching the physical joystick button on the monitor!
- Uses dual-layer DDC/CI (supports modern LG proprietary **VCP `0xF4`** and standard VESA **`0x60`**):
  - **`⌥ + 2` (Option + 2)**: Switch directly to **PS5 (HDMI 2)**.
  - **`⌥ + 1` (Option + 1)**: Switch back to **Mac (Type-C)**.
  - Also supports **HDMI 1** and **DisplayPort** from the Menu Bar app and CLI.

### 3. External Monitor Audio Volume Control
- macOS normally disables volume keys for external monitors.
- BetterDisplay Clone controls your LG monitor speakers over DDC/CI **VCP Code `0x62`**.

### 4. Sleek Menu Bar Control Center
- Real-time indicator displaying which screen currently has the cursor.
- Independent brightness sliders for both the Built-in Retina screen and the external LG HDR 4K monitor.
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
open BetterDisplayClone.app
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
| **`⌥ + 2`** | Switch to PS5 | Switches LG monitor to **HDMI 2** |
| **`⌥ + 1`** | Switch to Mac | Switches LG monitor back to **Type-C** |

---

## 🔒 Permissions

To intercept global media keys (F1/F2) and detect cursor position across screens, macOS requires **Accessibility Permissions**:
1. When launched, click **Grant Access** in the menu bar popover (or open **System Settings → Privacy & Security → Accessibility**).
2. Enable permissions for `BetterDisplayClone`.
