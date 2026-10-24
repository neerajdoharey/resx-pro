import AppKit
import SwiftUI
import IOKit.pwr_mgt

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    static func main() {
        let args = CommandLine.arguments
        
        // Handle CLI Commands
        if args.count > 1 {
            handleCLI(arguments: Array(args.dropFirst()))
            return
        }
        
        // Launch GUI Menu Bar App
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Agent mode: runs in menu bar without dock icon
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 ResX Pro starting...")
        
        // Setup Status Item in Menu Bar
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "ResX Pro")
            button.action = #selector(togglePopover)
            button.target = self
        }
        self.statusItem = item
        
        // Setup Popover with SwiftUI MenuBarView
        let p = NSPopover()
        p.contentSize = NSSize(width: 330, height: 600)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = p
        
        // Check and prompt for accessibility
        if !MediaKeyInterceptor.isAccessibilityTrusted() {
            print("⚠️ Accessibility permissions needed for keyboard brightness keys.")
            MediaKeyInterceptor.requestAccessibilityPermissions()
        }
        
        // Start Global Media Key & Hotkey Interceptor
        MediaKeyInterceptor.shared.start()
        
        print("✅ ResX Pro running in menu bar. Press F1/F2 or click the menu bar icon.")
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button, let p = popover else { return }
        if p.isShown {
            p.performClose(nil)
        } else {
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            p.contentViewController?.view.window?.makeKey()
        }
    }
    
    // MARK: - CLI Mode
    
    static func handleCLI(arguments: [String]) {
        let command = arguments[0].lowercased()
        let ddc = DDCService.shared
        let displays = ddc.discoverExternalDisplays()
        let ext = displays.first(where: { $0.location == "External" })
        
        switch command {
        case "list":
            print("\n📺 Connected Displays:")
            var displayCount: UInt32 = 0
            CGGetOnlineDisplayList(0, nil, &displayCount)
            var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
            CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)
            
            for id in displayIDs {
                let isBuiltin = ScreenDetector.isBuiltinDisplay(displayID: id)
                let matching = NSScreen.screens.first {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
                }
                let name = matching?.localizedName ?? (isBuiltin ? "Built-in Retina Display" : "External Display")
                print("  • \(name) (ID: \(id), Built-in: \(isBuiltin))")
            }
            print("\n🔌 DDC/CI Service Endpoints:")
            for d in displays {
                print("  • \(d.name) [\(d.location)] ID: \(d.id)")
            }
            
        case "get-brightness":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            if let b = ddc.getBrightness(service: target.service) {
                print("Brightness: \(b.current)% (Max: \(b.max))")
            } else {
                print("⚠️ Failed to read brightness.")
            }
            
        case "set-brightness":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            guard arguments.count > 1, let val = Int(arguments[1]) else {
                print("Usage: betterdisplay-clone set-brightness <0-100>")
                return
            }
            let effectiveVal = max(0, min(100, val))
            let ok = ddc.setBrightness(service: target.service, value: effectiveVal)
            print(ok ? "✅ Brightness set to \(effectiveVal)%" : "❌ Failed to set brightness.")
            
        case "get-input":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            if let inp = ddc.getInputSource(service: target.service) {
                print("Input Source: 0x\(String(format: "%02X", inp.current)) (\(inp.current)) | Max: 0x\(String(format: "%02X", inp.max))")
            } else {
                print("⚠️ Failed to read input source.")
            }
            
        case "switch-ps5", "switch-hdmi2":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            print("🎮 Switching input to PS5 (HDMI 2)...")
            let ok = ddc.switchLGInput(service: target.service, portName: "hdmi2")
            print(ok ? "✅ Switch command executed!" : "⚠️ Command sent (monitor should switch to HDMI 2).")
            
        case "switch-hdmi1":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            print("🎮 Switching input to HDMI 1...")
            let ok = ddc.switchLGInput(service: target.service, portName: "hdmi1")
            print(ok ? "✅ Switch command executed!" : "⚠️ Command sent (monitor should switch to HDMI 1).")
            
        case "switch-mac", "switch-typec":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            print("💻 Switching input to Mac (Type-C)...")
            let ok = ddc.switchLGInput(service: target.service, portName: "mac")
            print(ok ? "✅ Switch command executed!" : "⚠️ Command sent (monitor should switch to Type-C).")
            
        case "switch-dp", "switch-displayport":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            print("🖥️ Switching input to DisplayPort...")
            let ok = ddc.switchLGInput(service: target.service, portName: "dp")
            print(ok ? "✅ Switch command executed!" : "⚠️ Command sent (monitor should switch to DP).")
            
        case "set-input":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            guard arguments.count > 1 else {
                print("Usage: betterdisplay-clone set-input <hex or decimal, e.g. 0x11 or 17>")
                return
            }
            let rawStr = arguments[1]
            let val: UInt16?
            if rawStr.hasPrefix("0x") || rawStr.hasPrefix("0X") {
                val = UInt16(rawStr.dropFirst(2), radix: 16)
            } else {
                val = UInt16(rawStr)
            }
            guard let code = val else {
                print("Invalid input code.")
                return
            }
            print("Sending input switch command: 0x\(String(format: "%02X", code)) (\(code))...")
            let ok = ddc.setInputSource(service: target.service, value: code)
            print(ok ? "✅ Switch command sent!" : "❌ Failed to send switch command.")
            
        case "set-volume":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            guard arguments.count > 1, let val = Int(arguments[1]) else {
                print("Usage: betterdisplay-clone set-volume <0-100>")
                return
            }
            let ok = ddc.setVolume(service: target.service, value: val)
            print(ok ? "✅ Volume set to \(val)%" : "❌ Failed to set volume.")

        case "power-off", "power-standby":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            let ok = ddc.setPowerStandby(service: target.service)
            print(ok ? "✅ Monitor power standby command sent." : "❌ Failed to send power standby command.")

        case "power-on":
            guard let target = ext else {
                print("❌ No external display found.")
                return
            }
            var assertionID: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("ResX Pro Wake" as CFString, kIOPMUserActiveLocal, &assertionID)
            let ok = ddc.setPowerOn(service: target.service)
            print(ok ? "✅ Monitor power on command sent." : "❌ Failed to send power on command.")
            
        default:
            print("""
            BetterDisplay Clone CLI Usage:
              list                          List all connected displays and DDC endpoints
              get-brightness                Read external display brightness
              set-brightness <0-100>        Set external display brightness
              get-input                     Get current input source (VCP 0x60)
              switch-ps5                    Switch external monitor to PS5 (HDMI 1)
              switch-mac                    Switch external monitor to Mac (Type-C)
              set-input <hex/dec>           Set custom input source code
              set-volume <0-100>            Set external monitor audio volume
              power-standby / power-off     Put external monitor into standby
              power-on                      Power on external monitor
            
            Run without arguments to launch the Menu Bar application!
            """)
        }
    }
}
