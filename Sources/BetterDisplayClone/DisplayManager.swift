import Foundation
import AppKit
import CoreGraphics
import Combine
import IOKit.pwr_mgt

public struct ManagedDisplay: Identifiable, @unchecked Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
    public var brightness: Int // 0-100
    public var volume: Int     // 0-100
    public var inputSource: UInt16?
    public var ddcService: IOAVServiceRef?
    public var screen: NSScreen?
}

@MainActor
public final class DisplayManager: ObservableObject {
    public static let shared = DisplayManager()

    @Published public var displays: [ManagedDisplay] = []
    @Published public var activeDisplayID: CGDirectDisplayID = CGMainDisplayID()
    @Published public var mouseDisplayID: CGDirectDisplayID = CGMainDisplayID()
    @Published public var availableInputs: [DisplayInput] = []
    @Published public var inputsAreReported = false
    @Published public var inputProfileName: String?
    @Published public var inputStatus: String?
    @Published public var isSwitchingInput = false
    private var isReadingInput = false
    private var inputGeneration = UUID()

    private var brightnessBeforeBlackout: [CGDirectDisplayID: Int] = [:]
    @Published public var brightnessErrors: [CGDirectDisplayID: String] = [:]
    private var brightnessRequests: [CGDirectDisplayID: UUID] = [:]
    private var isDisplaySleeping: [CGDirectDisplayID: Bool] = [:]
    private var timer: Timer?
    private var screenChanges: AnyCancellable?

    public init(startMonitoring: Bool = true) {
        guard startMonitoring else { return }
        refreshDisplays()
        startMousePolling()
        screenChanges = NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshDisplays() }
            }
    }

    public func refreshDisplays() {
        var result: [ManagedDisplay] = []
        let ddcDisplays = DDCService.shared.discoverExternalDisplays()
        let externalServices = ddcDisplays.filter { $0.location == "External" }

        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount)

        var extIndex = 0
        for screenNum in displayIDs {
            let isBuiltin = ScreenDetector.isBuiltinDisplay(displayID: screenNum)
            let matchingScreen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == screenNum
            }

            let name: String
            if let profile = Self.knownMonitorName(vendor: CGDisplayVendorNumber(screenNum), product: CGDisplayModelNumber(screenNum), serial: CGDisplaySerialNumber(screenNum)) {
                name = profile
            } else if let localized = matchingScreen?.localizedName {
                name = localized
            } else if isBuiltin {
                name = "Built-in Retina Display"
            } else {
                name = "External Display"
            }

            let savedBrightness = UserDefaults.standard.object(forKey: "display_brightness_\(screenNum)") as? Int
            var initialBrightness = savedBrightness ?? (isBuiltin ? 90 : 75)
            var ddcRef: IOAVServiceRef? = nil
            var inputCode: UInt16? = nil
            let initialVolume = 30

            if isBuiltin {
                if let b = DisplayServicesBridge.shared.getBrightness(displayID: screenNum) {
                    initialBrightness = Int(round(b * 100.0))
                }
            } else {
                if extIndex < externalServices.count {
                    let s = externalServices[extIndex].service
                    ddcRef = s
                    extIndex += 1

                    if let ddcB = DDCService.shared.getBrightness(service: s) {
                        initialBrightness = ddcB.current
                    }
                    if let ddcInp = DDCService.shared.getInputSource(service: s) {
                        inputCode = ddcInp.current
                    }
                }
            }

            // A hardware read cannot describe a software shade or blackout.
            let previous = displays.first(where: { $0.id == screenNum })?.brightness ?? savedBrightness
            initialBrightness = Self.reconciledBrightness(previous: previous, hardware: initialBrightness)
            ShadeManager.shared.setShade(displayID: screenNum, alpha: CGFloat(max(0, -initialBrightness)) / 200)

            let managed = ManagedDisplay(
                id: screenNum,
                name: name,
                isBuiltin: isBuiltin,
                brightness: initialBrightness,
                volume: initialVolume,
                inputSource: inputCode,
                ddcService: ddcRef,
                screen: matchingScreen
            )
            result.append(managed)
        }
        // Keep blacked-out screens addressable while their video link is unavailable.
        for var missing in displays where !result.contains(where: { $0.id == missing.id }) && missing.brightness < 0 {
            missing.screen = nil
            missing.ddcService = nil
            result.append(missing)
        }
        self.displays = result
        if let external = result.first(where: { !$0.isBuiltin && $0.ddcService != nil }), let service = external.ddcService {
            let discovered = DDCService.shared.getAvailableInputs(service: service)
            inputProfileName = Self.knownMonitorName(vendor: CGDisplayVendorNumber(external.id), product: CGDisplayModelNumber(external.id), serial: CGDisplaySerialNumber(external.id))
            inputsAreReported = !discovered.isEmpty
            // The user identified this exact unit from its physical label. Its only
            // video connectors are HDMI 1, HDMI 2 and DisplayPort (no USB-C).
            availableInputs = inputProfileName != nil ? Self.standardInputs : (discovered.isEmpty ? Self.standardInputs : discovered)
            if let code = external.inputSource, !availableInputs.contains(where: { $0.code == code }) {
                availableInputs.append(.fromVCPCode(code))
            }
        } else {
            availableInputs = []
            inputsAreReported = false
            inputProfileName = nil
        }
    }

    static func reconciledBrightness(previous: Int?, hardware: Int) -> Int {
        if let previous, previous < 0 { return max(-200, previous) }
        return hardware
    }

    // EDID product names are generic across LG models; scope the user-confirmed
    // profile to this unit, not every monitor named "LG HDR 4K".
    static func knownMonitorName(vendor: UInt32, product: UInt32, serial: UInt32) -> String? {
        vendor == 0x1E6D && product == 0x774F && serial == 0x1FE19 ? "LG 32UN650-W" : nil
    }

    static let standardInputs: [DisplayInput] = [
        .fromVCPCode(0x11), .fromVCPCode(0x12), .fromVCPCode(0x0F)
    ]

    private func startMousePolling() {
        // Poll mouse location to track active screen
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let currentUnderMouse = ScreenDetector.getDisplayUnderMouse()
                if self.mouseDisplayID != currentUnderMouse {
                    self.mouseDisplayID = currentUnderMouse
                }
            }
        }
    }

    public func setBrightness(displayID: CGDirectDisplayID, value: Int, showHUD: Bool = false) {
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        let target = displays[idx]
        let clamped = max(-200, min(100, value))
        if clamped == -200 && target.brightness > -200 {
            brightnessBeforeBlackout[displayID] = max(15, target.brightness)
        }
        displays[idx].brightness = clamped
        UserDefaults.standard.set(clamped, forKey: "display_brightness_\(displayID)")
        brightnessErrors[displayID] = nil
        let request = UUID()
        brightnessRequests[displayID] = request

        // Blackout is an overlay only. Leave the backlight reachable and restore it on exit.
        if clamped > -200 {
            let hardwareValue = max(0, clamped)
            if target.isBuiltin {
                if !DisplayServicesBridge.shared.setBrightness(displayID: displayID, brightness: Float(hardwareValue) / 100) {
                    brightnessErrors[displayID] = "Could not change display brightness. Try again."
                }
            } else if let service = target.ddcService {
                writeBrightness(displayID: displayID, service: service, value: hardwareValue, request: request, retry: true)
            } else {
                brightnessErrors[displayID] = "Monitor unavailable. Reconnect or turn it on using its power button, then retry."
            }
        }

        // Software Shade Dimming below 0 down to -200 (pitch black)
        if clamped < 0 {
            let alpha = CGFloat(-clamped) / 200.0
            ShadeManager.shared.setShade(displayID: displayID, alpha: alpha)
        } else {
            ShadeManager.shared.setShade(displayID: displayID, alpha: 0.0)
        }

        isDisplaySleeping[displayID] = clamped == -200

        if showHUD {
            let icon: String
            if clamped <= -200 {
                icon = "power.circle.fill"
            } else if clamped < 0 {
                icon = "moon.fill"
            } else {
                icon = "sun.max.fill"
            }
            OSDManager.shared.show(displayName: target.name, value: clamped, icon: icon, screen: target.screen)
        }
    }

    public func adjustActiveScreenBrightness(delta: Int) {
        let targetID = ScreenDetector.activeDisplayID()
        adjustScreenBrightness(displayID: targetID, delta: delta)
    }

    public var hasSleepingDisplays: Bool {
        return displays.contains(where: { isDisplaySleeping[$0.id] == true || $0.brightness <= -200 })
    }

    /// Remove blackout independently of hardware availability; never send DDC power-off for it.
    public func wakeSleepingDisplays(targetDisplayID: CGDirectDisplayID? = nil) {
        let targets = displays.filter {
            targetDisplayID == $0.id || (targetDisplayID == nil && $0.brightness <= -200)
        }
        for display in targets {
            ShadeManager.shared.setShade(displayID: display.id, alpha: 0)
            if display.ddcService == nil && !display.isBuiltin { refreshDisplays() }
            setBrightness(displayID: display.id, value: brightnessBeforeBlackout[display.id] ?? 50, showHUD: true)
        }
    }

    private func writeBrightness(displayID: CGDirectDisplayID, service: IOAVServiceRef, value: Int, request: UUID, retry: Bool) {
        DDCService.shared.setBrightnessAsync(service: service, value: value) { [weak self] success, actual in
            Task { @MainActor [weak self] in
                guard let self, self.brightnessRequests[displayID] == request else { return }
                if !success && retry {
                    // Only reacquire by position when there is exactly one external monitor.
                    let candidates = DDCService.shared.discoverExternalDisplays().filter { $0.location == "External" }
                    if self.displays.filter({ !$0.isBuiltin }).count == 1, candidates.count == 1,
                       let index = self.displays.firstIndex(where: { $0.id == displayID }) {
                        let fresh = candidates[0].service
                        self.displays[index].ddcService = fresh
                        self.writeBrightness(displayID: displayID, service: fresh, value: value, request: request, retry: false)
                        return
                    }
                }
                if !success {
                    self.brightnessErrors[displayID] = "Monitor did not accept brightness. Check its power and DDC/CI setting, then retry."
                } else if let actual, abs(actual - value) > 1 {
                    self.brightnessErrors[displayID] = "Monitor reports \(actual)% brightness; requested \(value)%."
                } else if actual == nil {
                    self.brightnessErrors[displayID] = "Brightness command sent; this monitor did not confirm its value."
                } else {
                    self.brightnessErrors[displayID] = nil
                }
            }
        }
    }

    private var lastBrightnessAdjustTime: TimeInterval = 0
    public func adjustBrightnessDebounced(displayID: CGDirectDisplayID, delta: Int) {
        let now = Date().timeIntervalSince1970
        guard now - lastBrightnessAdjustTime > 0.04 else { return }
        lastBrightnessAdjustTime = now

        // If the user presses brightness UP and ANY display is sleeping/blacked out, wake it up immediately!
        if delta > 0 && hasSleepingDisplays {
            wakeSleepingDisplays()
            return
        }

        adjustScreenBrightness(displayID: displayID, delta: delta)
    }

    public func adjustScreenBrightness(displayID: CGDirectDisplayID, delta: Int) {
        if !displays.contains(where: { $0.id == displayID }) { refreshDisplays() }
        guard let display = displays.first(where: { $0.id == displayID }) else { return }

        // If display is currently sleeping or at -200, and user increases brightness, wake it immediately to visible level!
        if (isDisplaySleeping[displayID] == true || display.brightness <= -200) && delta > 0 {
            wakeSleepingDisplays(targetDisplayID: displayID)
            return
        }

        setBrightness(displayID: displayID, value: display.brightness + delta, showHUD: true)
    }

    public func setVolume(displayID: CGDirectDisplayID, value: Int, showHUD: Bool = false) {
        guard let idx = displays.firstIndex(where: { $0.id == displayID }) else { return }
        let clamped = max(0, min(100, value))
        displays[idx].volume = clamped

        let target = displays[idx]
        if let s = target.ddcService {
            _ = DDCService.shared.setVolume(service: s, value: clamped)
        }

        if showHUD {
            OSDManager.shared.show(displayName: target.name, value: clamped, icon: "speaker.wave.3.fill", screen: target.screen)
        }
    }

    public func switchInput(displayID: CGDirectDisplayID? = nil, portName: String) -> Bool {
        let targetDisplay: ManagedDisplay?
        if let dID = displayID {
            targetDisplay = displays.first(where: { $0.id == dID })
        } else {
            // Find external display with DDC service
            targetDisplay = displays.first(where: { !$0.isBuiltin && $0.ddcService != nil })
        }

        guard let target = targetDisplay, let s = target.ddcService else {
            print("No valid external DDC service available to switch input.")
            return false
        }

        return DDCService.shared.switchLGInput(service: s, portName: portName)
    }

    public func refreshInputState() {
        guard !isReadingInput, !isSwitchingInput,
              let target = displays.first(where: { !$0.isBuiltin }), target.ddcService != nil else { return }
        isReadingInput = true
        let generation = inputGeneration
        Task {
            let current = await Task.detached {
                DDCService.shared.getInputSource(service: target.ddcService!)?.current
            }.value
            if generation == inputGeneration, let index = displays.firstIndex(where: { $0.id == target.id }) {
                displays[index].inputSource = current
            }
            isReadingInput = false
        }
    }

    public func switchInputAsync(input: DisplayInput) {
        guard !isSwitchingInput, let target = displays.first(where: { !$0.isBuiltin }), target.ddcService != nil else {
            inputStatus = "Monitor control is unavailable."
            return
        }
        inputGeneration = UUID()
        isSwitchingInput = true
        inputStatus = "Switching to \(input.name)…"
        Task {
            let result = await Task.detached {
                let success = DDCService.shared.switchLGInput(service: target.ddcService!, portName: input.name)
                try? await Task.sleep(for: .milliseconds(600))
                let current = DDCService.shared.getInputSource(service: target.ddcService!)?.current
                return (success, current)
            }.value
            if let index = displays.firstIndex(where: { $0.id == target.id }) {
                displays[index].inputSource = result.1
            }
            if !result.0 {
                inputStatus = "Input switch failed. Check the monitor’s DDC/CI setting."
            } else if result.1 == input.code {
                inputStatus = "\(input.name) selected."
            } else if result.1 == nil {
                inputStatus = "Command sent. The monitor is not reporting its selected input."
            } else {
                inputStatus = "The monitor did not confirm the requested input."
            }
            isSwitchingInput = false
        }
    }

    public func switchInput(displayID: CGDirectDisplayID? = nil, input: DisplayInput) -> Bool {
        let targetDisplay: ManagedDisplay?
        if let dID = displayID {
            targetDisplay = displays.first(where: { $0.id == dID })
        } else {
            targetDisplay = displays.first(where: { !$0.isBuiltin && $0.ddcService != nil })
        }
        guard let service = targetDisplay?.ddcService else { return false }
        return DDCService.shared.setInputSource(service: service, value: input.code)
    }

    public func switchInput(named name: String) -> Bool {
        guard let input = availableInputs.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return false
        }
        return switchInput(input: input)
    }
}
