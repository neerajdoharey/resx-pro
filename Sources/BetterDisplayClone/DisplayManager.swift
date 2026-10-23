import Foundation
import AppKit
import CoreGraphics
import Combine

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
    
    private var timer: Timer?
    
    public init() {
        refreshDisplays()
        startMousePolling()
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
            if let localized = matchingScreen?.localizedName {
                name = localized
            } else if isBuiltin {
                name = "Built-in Retina Display"
            } else {
                name = "LG HDR 4K Monitor"
            }
            
            var initialBrightness = 50
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
        self.displays = result
    }
    
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
        let clamped = max(0, min(100, value))
        displays[idx].brightness = clamped
        
        let target = displays[idx]
        if target.isBuiltin {
            _ = DisplayServicesBridge.shared.setBrightness(displayID: displayID, brightness: Float(clamped) / 100.0)
        } else if let s = target.ddcService {
            _ = DDCService.shared.setBrightness(service: s, value: clamped)
        }
        
        if showHUD {
            OSDManager.shared.show(displayName: target.name, value: clamped, icon: "sun.max.fill", screen: target.screen)
        }
    }
    
    public func adjustActiveScreenBrightness(delta: Int) {
        let targetID = ScreenDetector.getDisplayUnderMouse()
        guard let display = displays.first(where: { $0.id == targetID }) else {
            if let first = displays.first {
                setBrightness(displayID: first.id, value: first.brightness + delta, showHUD: true)
            }
            return
        }
        setBrightness(displayID: targetID, value: display.brightness + delta, showHUD: true)
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
}
