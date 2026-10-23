import AppKit
import CoreGraphics
import Carbon

public final class MediaKeyInterceptor: @unchecked Sendable {
    public static let shared = MediaKeyInterceptor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var carbonHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var permissionPollTimer: Timer?
    
    // Carbon Hotkey Identifiers
    private let hotKeySignature: OSType = 0x4244434B // "BDCK" (BetterDisplayClone Keys)
    private let hotKeyIDMac: UInt32 = 1
    private let hotKeyIDPS5: UInt32 = 2
    private let hotKeyIDMacPad: UInt32 = 11
    private let hotKeyIDPS5Pad: UInt32 = 12
    
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
        // 1. Register Carbon Global Hotkeys (Option+1 & Option+2)
        // Carbon Hotkeys work GLOBALLY and do NOT require Accessibility permissions!
        registerCarbonHotkeys()
        
        // 2. Start Event Tap for Brightness Media Keys (F1/F2)
        startEventTap()
        
        // 3. If Event Tap couldn't start yet, poll until permissions are active
        if eventTap == nil {
            setupPermissionPolling()
        }
    }
    
    public func stop() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        
        unregisterCarbonHotkeys()
        stopEventTap()
    }
    
    // MARK: - Carbon Global Hotkeys (Works unconditionally across all apps)
    
    private func registerCarbonHotkeys() {
        guard carbonHandlerRef == nil else { return }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return noErr }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userData).takeUnretainedValue()
                
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr {
                    interceptor.handleHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &carbonHandlerRef
        )
        
        if status != noErr {
            print("⚠️ InstallEventHandler returned status: \(status)")
        }
        
        // Keycodes on macOS:
        // 18 = '1' (kVK_ANSI_1), 19 = '2' (kVK_ANSI_2)
        // 83 = Keypad 1 (kVK_ANSI_Keypad1), 84 = Keypad 2 (kVK_ANSI_Keypad2)
        // Modifiers: optionKey = 0x0800
        registerSingleHotKey(keyCode: 18, modifiers: UInt32(optionKey), id: hotKeyIDMac)
        registerSingleHotKey(keyCode: 19, modifiers: UInt32(optionKey), id: hotKeyIDPS5)
        registerSingleHotKey(keyCode: 83, modifiers: UInt32(optionKey), id: hotKeyIDMacPad)
        registerSingleHotKey(keyCode: 84, modifiers: UInt32(optionKey), id: hotKeyIDPS5Pad)
        
        print("✅ Carbon global hotkeys (Option+1 -> Mac, Option+2 -> PS5) registered successfully.")
    }
    
    private func registerSingleHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if regStatus == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        } else {
            print("⚠️ Failed to register hotkey for keyCode: \(keyCode), status: \(regStatus)")
        }
    }
    
    private func unregisterCarbonHotkeys() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        
        if let h = carbonHandlerRef {
            RemoveEventHandler(h)
            carbonHandlerRef = nil
        }
    }
    
    public func handleHotKey(id: UInt32) {
        Task { @MainActor in
            switch id {
            case hotKeyIDMac, hotKeyIDMacPad:
                print("💻 Hotkey Option+1 triggered: Switching to Mac (Type-C)...")
                let success = DisplayManager.shared.switchInput(portName: "mac")
                OSDManager.shared.showStatus(
                    title: "LG HDR 4K",
                    subtitle: success ? "Mac (Type-C)" : "Switching to Mac...",
                    icon: "laptopcomputer"
                )
            case hotKeyIDPS5, hotKeyIDPS5Pad:
                print("🎮 Hotkey Option+2 triggered: Switching to PS5 (HDMI 2)...")
                let success = DisplayManager.shared.switchInput(portName: "hdmi2")
                OSDManager.shared.showStatus(
                    title: "LG HDR 4K",
                    subtitle: success ? "PS5 (HDMI 2)" : "Switching to PS5...",
                    icon: "gamecontroller.fill"
                )
            default:
                break
            }
        }
    }
    
    // MARK: - CGEvent Tap (For F1 / F2 Brightness Media Keys)
    
    public func startEventTap() {
        guard eventTap == nil else { return }
        
        // Listen to systemDefined events (media keys, raw 14) and keyDown events
        let eventMask: CGEventMask = (1 << 14) | (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
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
            print("ℹ️ CGEvent.tapCreate pending Accessibility permissions in System Settings.")
            return
        }
        
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.eventTap = tap
        self.runLoopSource = source
        print("✅ Global MediaKeyInterceptor event tap started successfully.")
        
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
    
    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
    }
    
    private func setupPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if MediaKeyInterceptor.isAccessibilityTrusted() {
                DispatchQueue.main.async {
                    self.startEventTap()
                }
            }
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
        
        // 2. Secondary fallback for Option + 1 and Option + 2 in CGEvent tap
        if type == .keyDown {
            let flags = event.flags
            let isOption = flags.contains(.maskAlternate)
            let isControl = flags.contains(.maskControl)
            let isCommand = flags.contains(.maskCommand)
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            if isOption && !isCommand && !isControl {
                if keyCode == 19 || keyCode == 84 { // '2' or Keypad 2
                    handleHotKey(id: hotKeyIDPS5)
                    return nil
                } else if keyCode == 18 || keyCode == 83 { // '1' or Keypad 1
                    handleHotKey(id: hotKeyIDMac)
                    return nil
                }
            }
        }
        
        return Unmanaged.passRetained(event)
    }
}
