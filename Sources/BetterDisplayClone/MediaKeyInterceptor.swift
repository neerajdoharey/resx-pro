import AppKit
import CoreGraphics
import Carbon

public final class MediaKeyInterceptor: @unchecked Sendable {
    public static let shared = MediaKeyInterceptor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    public init() {}
    
    /// Checks if the application has accessibility permissions
    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Requests accessibility permissions with system prompt dialog
    public static func requestAccessibilityPermissions() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    public func start() {
        guard eventTap == nil else { return }
        
        // Listen to systemDefined events (media keys, raw 14) and keyDown events
        let eventMask: CGEventMask = (1 << 14) | (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return interceptor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ CGEvent.tapCreate failed. App needs Accessibility permissions in System Settings.")
            return
        }
        
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.eventTap = tap
        self.runLoopSource = source
        print("✅ Global MediaKeyInterceptor started successfully.")
    }
    
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        // 1. Check for standard Brightness Media Keys (F1 / F2 / Touch Bar, rawType 14)
        if type.rawValue == 14 {
            if let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 {
                let data1 = nsEvent.data1
                let keyCode = (data1 & 0xFFFF0000) >> 16
                let keyFlags = data1 & 0x0000FFFF
                let keyState = (keyFlags & 0xFF00) >> 8
                let isKeyDown = keyState == 0x0A // Key down event
                
                // KeyCodes: 2 = NX_KEYTYPE_BRIGHTNESS_UP, 3 = NX_KEYTYPE_BRIGHTNESS_DOWN
                if isKeyDown {
                    if keyCode == 2 {
                        Task { @MainActor in
                            DisplayManager.shared.adjustActiveScreenBrightness(delta: +6)
                        }
                        return nil // Intercepted: suppress system default
                    } else if keyCode == 3 {
                        Task { @MainActor in
                            DisplayManager.shared.adjustActiveScreenBrightness(delta: -6)
                        }
                        return nil // Intercepted: suppress system default
                    }
                }
            }
        }
        
        // 2. Check for Global Hotkeys for Input Switching:
        // Option + 1: Switch to Mac (Type-C)
        // Option + 2: Switch to PS5 (HDMI 1)
        if type == .keyDown {
            let flags = event.flags
            let isOption = flags.contains(.maskAlternate)
            let isControl = flags.contains(.maskControl)
            let isCommand = flags.contains(.maskCommand)
            
            // Keycode 18 is '1', keycode 19 is '2' on US Keyboard
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            if isOption && !isCommand && !isControl {
                if keyCode == 19 { // '2' -> PS5 on HDMI 2
                    Task { @MainActor in
                        print("🎮 Hotkey Option+2 pressed: Switching to PS5 (HDMI 2)...")
                        _ = DisplayManager.shared.switchInput(portName: "hdmi2")
                    }
                    return nil
                } else if keyCode == 18 { // '1' -> Mac Type-C
                    Task { @MainActor in
                        print("💻 Hotkey Option+1 pressed: Switching to Mac (Type-C)...")
                        _ = DisplayManager.shared.switchInput(portName: "mac")
                    }
                    return nil
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
}
