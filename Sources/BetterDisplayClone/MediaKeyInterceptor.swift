import AppKit
import CoreGraphics
import Carbon

public struct ShortcutBinding: Codable, Equatable, Identifiable {
    public var inputCode: UInt16
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var id: UInt16 { inputCode }
    public var label: String

    public init(inputCode: UInt16, keyCode: UInt32, modifiers: UInt32, label: String) {
        self.inputCode = inputCode
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }
}

public final class MediaKeyInterceptor: @unchecked Sendable {
    public static let shared = MediaKeyInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var carbonHandlerRef: EventHandlerRef?
    private var registeredHotKeys: [(id: UInt32, ref: EventHotKeyRef)] = []
    private var permissionPollTimer: Timer?

    // Carbon Hotkey Identifiers
    private let hotKeySignature: OSType = 0x4244434B // "BDCK" (BetterDisplayClone Keys)
    private let hotKeyBrightnessDownID: UInt32 = 1
    private let hotKeyBrightnessUpID: UInt32 = 2
    private let hotKeyBrightnessDownOptID: UInt32 = 3
    private let hotKeyBrightnessUpOptID: UInt32 = 4
    private var brightnessHotKeyRefs: [EventHotKeyRef] = []

    private var bindings: [ShortcutBinding] = []
    private var bindingsByHotKeyID: [UInt32: ShortcutBinding] = [:]
    private var started = false
    public private(set) var registrationStatus: [UInt16: Bool] = [:]

    public init() {
        let saved = UserDefaults.standard.data(forKey: "displayShortcutBindings")
            .flatMap { try? JSONDecoder().decode([ShortcutBinding].self, from: $0) }
        bindings = saved ?? [
            ShortcutBinding(inputCode: 0xD0, keyCode: 18, modifiers: UInt32(optionKey), label: "USB-C"),
            ShortcutBinding(inputCode: 0x12, keyCode: 19, modifiers: UInt32(optionKey), label: "HDMI 2")
        ]
    }

    /// Checks if the application has accessibility permissions
    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Requests accessibility permissions with system prompt dialog and opens Settings
    public static func openAccessibilitySettings() {
        requestAccessibilityPermissions()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Requests accessibility permissions with system prompt dialog
    public static func requestAccessibilityPermissions() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public var isEventTapActive: Bool {
        return eventTap != nil
    }

    public func start() {
        started = true
        // 1. Register configured Carbon global hotkeys.
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
        started = false
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

        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 100)
            bindingsByHotKeyID[id] = binding
            registerSingleHotKey(binding, id: id)
        }

        // Register Carbon fallback hotkeys for F1 (Brightness Down) & F2 (Brightness Up)
        // Works unconditionally without Accessibility permissions!
        registerBrightnessHotKey(keyCode: 122, modifiers: 0, id: hotKeyBrightnessDownID)
        registerBrightnessHotKey(keyCode: 120, modifiers: 0, id: hotKeyBrightnessUpID)
        registerBrightnessHotKey(keyCode: 122, modifiers: UInt32(optionKey), id: hotKeyBrightnessDownOptID)
        registerBrightnessHotKey(keyCode: 120, modifiers: UInt32(optionKey), id: hotKeyBrightnessUpOptID)
    }

    private func registerBrightnessHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
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
            brightnessHotKeyRefs.append(ref)
        }
    }

    private func registerSingleHotKey(_ binding: ShortcutBinding, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if regStatus == noErr, let ref = hotKeyRef {
            registeredHotKeys.append((id, ref))
            registrationStatus[binding.inputCode] = true
        } else {
            registrationStatus[binding.inputCode] = false
            print("⚠️ Hotkey registration failed for \(binding.label), status: \(regStatus)")
        }
    }

    private func unregisterCarbonHotkeys() {
        for entry in registeredHotKeys {
            UnregisterEventHotKey(entry.ref)
        }
        for ref in brightnessHotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        registeredHotKeys.removeAll()
        brightnessHotKeyRefs.removeAll()
        bindingsByHotKeyID.removeAll()
        registrationStatus.removeAll()

        if let h = carbonHandlerRef {
            RemoveEventHandler(h)
            carbonHandlerRef = nil
        }
    }

    @discardableResult
    public func checkShortcut(_ binding: ShortcutBinding) -> Bool {
        let existing = registeredHotKeys
        for entry in existing { UnregisterEventHotKey(entry.ref) }
        registeredHotKeys.removeAll()
        var ref: EventHotKeyRef?
        let probeID = EventHotKeyID(signature: hotKeySignature, id: UInt32.max)
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, probeID, GetEventDispatcherTarget(), 0, &ref)
        if let ref { UnregisterEventHotKey(ref) }
        if started {
            bindingsByHotKeyID.removeAll()
            for (index, configured) in bindings.enumerated() {
                let id = UInt32(index + 100)
                bindingsByHotKeyID[id] = configured
                registerSingleHotKey(configured, id: id)
            }
        }
        return status == noErr
    }

    public func shortcutIsRegistered(_ inputCode: UInt16) -> Bool? {
        registrationStatus[inputCode]
    }

    public func configureShortcuts(_ newBindings: [ShortcutBinding]) {
        let unique = Dictionary(grouping: newBindings, by: { "\($0.keyCode):\($0.modifiers)" })
        guard unique.values.allSatisfy({ $0.count == 1 }) else { return }
        unregisterCarbonHotkeys()
        bindings = newBindings
        if let data = try? JSONEncoder().encode(newBindings) {
            UserDefaults.standard.set(data, forKey: "displayShortcutBindings")
        }
        if started { registerCarbonHotkeys() }
    }

    public var configuredShortcuts: [ShortcutBinding] { bindings }

    public func setShortcut(_ binding: ShortcutBinding) -> Bool {
        var updated = bindings.filter { $0.inputCode != binding.inputCode }
        updated.append(binding)
        let keys = updated.map { "\($0.keyCode):\($0.modifiers)" }
        guard Set(keys).count == keys.count else { return false }
        guard updated.allSatisfy({ checkShortcut($0) }) else { return false }
        configureShortcuts(updated)
        return true
    }

    public func handleHotKey(id: UInt32) {
        Task { @MainActor in
            if id == self.hotKeyBrightnessDownID || id == self.hotKeyBrightnessDownOptID {
                let targetID = ScreenDetector.activeDisplayID()
                DisplayManager.shared.adjustBrightnessDebounced(displayID: targetID, delta: -5)
                return
            }
            if id == self.hotKeyBrightnessUpID || id == self.hotKeyBrightnessUpOptID {
                let targetID = ScreenDetector.activeDisplayID()
                DisplayManager.shared.adjustBrightnessDebounced(displayID: targetID, delta: 5)
                return
            }
            guard let binding = bindingsByHotKeyID[id] else { return }
            _ = DisplayManager.shared.switchInput(input: DisplayInput.fromVCPCode(binding.inputCode))
            OSDManager.shared.showStatus(title: "External Display", subtitle: binding.label, icon: "display")
        }
    }

    // MARK: - CGEvent Tap (For F1 / F2 Brightness Media Keys)

    public func startEventTap() {
        guard eventTap == nil else { return }

        // Listen to systemDefined events (media keys, raw 14) and keyDown events
        let eventMask: CGEventMask = (1 << 14) | (1 << CGEventType.keyDown.rawValue)
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handleEvent(proxy: proxy, type: type, event: event)
        }

        // Try session event tap first (only requires Accessibility permission),
        // fallback to HID event tap (which requires Input Monitoring).
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPointer
        ) ?? CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPointer
        )

        guard let tap = tap else {
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
            if self.eventTap == nil {
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
                if keyCode == 2 || keyCode == 3 {
                    // Always identify the screen directly under the mouse pointer
                    let targetID = ScreenDetector.activeDisplayID()
                    if isKeyDown {
                        let delta = keyCode == 2 ? 5 : -5
                        Task { @MainActor in
                            DisplayManager.shared.adjustBrightnessDebounced(displayID: targetID, delta: delta)
                        }
                    }
                    // Always consume event so macOS does not adjust the built-in laptop screen
                    return nil
                }
            }
        }

        // 2. Check for standard Function Keys (F1 / F2 as key events: 122 = F1, 120 = F2)
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let isCmd = flags.contains(.maskCommand)
            let isCtrl = flags.contains(.maskControl)
            if !isCmd && !isCtrl && (keyCode == 122 || keyCode == 120) {
                let targetID = ScreenDetector.activeDisplayID()
                let delta = keyCode == 120 ? 5 : -5
                Task { @MainActor in
                    DisplayManager.shared.adjustBrightnessDebounced(displayID: targetID, delta: delta)
                }
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }
}
