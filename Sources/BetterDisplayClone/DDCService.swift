import Foundation
import IOKit
import CoreGraphics

public typealias IOAVServiceRef = CFTypeRef

@_silgen_name("IOAVServiceCreate")
func IOAVServiceCreate(_ allocator: CFAllocator?) -> Unmanaged<IOAVServiceRef>?

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<IOAVServiceRef>?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVServiceRef, _ chipAddress: UInt32, _ offset: UInt32, _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> IOReturn

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVServiceRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32) -> IOReturn

public struct DDCVCP {
    public static let brightness: UInt8 = 0x10
    public static let contrast: UInt8 = 0x12
    public static let inputSource: UInt8 = 0x60
    public static let audioVolume: UInt8 = 0x62
    public static let powerMode: UInt8 = 0xD6
}

public struct LGInputCode {
    // Standard VESA VCP 0x60 codes
    public static let vesaHDMI1: UInt16 = 0x11       // 17
    public static let vesaHDMI2: UInt16 = 0x12       // 18
    public static let vesaDisplayPort: UInt16 = 0x0F // 15
    public static let vesaUsbC: UInt16 = 0xD0        // 208 (or 0x1B)

    // LG Proprietary VCP 0xF4 codes (Modern UltraGear / 4K monitors)
    public static let lgAltHDMI1: UInt16 = 0x90       // 144
    public static let lgAltHDMI2: UInt16 = 0x91       // 145
    public static let lgAltDisplayPort: UInt16 = 0xD0 // 208
    public static let lgAltUsbC: UInt16 = 0xD1        // 209
}

public final class DDCService: @unchecked Sendable {
    public static let shared = DDCService()
    
    private let ddc7BitAddress: UInt8 = 0x37
    private let ddcDataAddress: UInt8 = 0x51
    
    public struct DiscoveredDisplay: @unchecked Sendable {
        public let id: String
        public let name: String
        public let location: String
        public let service: IOAVServiceRef
    }
    
    public init() {}
    
    /// Discovers all external displays with active IOAVService endpoints
    public func discoverExternalDisplays() -> [DiscoveredDisplay] {
        var displays: [DiscoveredDisplay] = []
        let matchingDict = IOServiceMatching("DCPAVServiceProxy")
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            print("Failed to get matching DCPAVServiceProxy services: \(result)")
            return displays
        }
        defer { IOObjectRelease(iterator) }
        
        var serviceEntry = IOIteratorNext(iterator)
        var index = 0
        while serviceEntry != 0 {
            defer {
                IOObjectRelease(serviceEntry)
                serviceEntry = IOIteratorNext(iterator)
            }
            
            // Check location property ("Embedded" vs "External")
            var location = "Unknown"
            if let locProp = IORegistryEntryCreateCFProperty(serviceEntry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                location = locProp
            }
            
            // For external monitors, create IOAVService instance
            if let avServiceUnmanaged = IOAVServiceCreateWithService(kCFAllocatorDefault, serviceEntry) {
                let avService = avServiceUnmanaged.takeRetainedValue()
                let display = DiscoveredDisplay(
                    id: "DCPAV_\(index)_\(location)",
                    name: location == "External" ? "External Monitor" : "Embedded Display",
                    location: location,
                    service: avService
                )
                displays.append(display)
                index += 1
            }
        }
        return displays
    }
    
    /// Calculates standard DDC/CI XOR checksum
    private func checksum(chk: UInt8, data: inout [UInt8], start: Int, end: Int) -> UInt8 {
        var chkd: UInt8 = chk
        for i in start...end {
            chkd ^= data[i]
        }
        return chkd
    }
    
    /// Writes a DDC/CI VCP command to an external display
    @discardableResult
    public func writeVCP(service: IOAVServiceRef, command: UInt8, value: UInt16, retries: Int = 3, dataAddress: UInt8 = 0x51) -> Bool {
        let send: [UInt8] = [command, UInt8(value >> 8), UInt8(value & 0xFF)]
        
        // Packet: [0x80 | length, length] + payload + [checksum]
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let initialChk: UInt8 = send.count == 1 ? (ddc7BitAddress << 1) : ((ddc7BitAddress << 1) ^ dataAddress)
        packet[packet.count - 1] = checksum(chk: initialChk, data: &packet, start: 0, end: packet.count - 2)
        
        for _ in 0...retries {
            usleep(15000) // 15ms DDC pacing
            let status = IOAVServiceWriteI2C(
                service,
                UInt32(ddc7BitAddress),
                UInt32(dataAddress),
                &packet,
                UInt32(packet.count)
            )
            if status == kIOReturnSuccess {
                return true
            }
            usleep(25000)
        }
        return false
    }

    /// Robust input switcher specifically optimized for LG displays (supports both VESA 0x60 & LG Alt 0xF4)
    @discardableResult
    public func switchLGInput(service: IOAVServiceRef, portName: String) -> Bool {
        var vesaCode: UInt16 = LGInputCode.vesaHDMI2
        var altCode: UInt16 = LGInputCode.lgAltHDMI2
        
        let p = portName.lowercased()
        if p.contains("hdmi1") {
            vesaCode = LGInputCode.vesaHDMI1
            altCode = LGInputCode.lgAltHDMI1
        } else if p.contains("hdmi2") || p.contains("ps5") {
            vesaCode = LGInputCode.vesaHDMI2
            altCode = LGInputCode.lgAltHDMI2
        } else if p.contains("dp") || p.contains("displayport") {
            vesaCode = LGInputCode.vesaDisplayPort
            altCode = LGInputCode.lgAltDisplayPort
        } else if p.contains("mac") || p.contains("typec") || p.contains("usbc") {
            vesaCode = LGInputCode.vesaUsbC
            altCode = LGInputCode.lgAltUsbC
        }
        
        print("🔄 Switching LG monitor input to \(portName) (VCP 0xF4: 0x\(String(format: "%02X", altCode)) / VCP 0x60: 0x\(String(format: "%02X", vesaCode)))...")
        
        // 1. Send LG proprietary VCP 0xF4 (with address 0x51 and 0x50)
        _ = writeVCP(service: service, command: 0xF4, value: altCode, retries: 2, dataAddress: 0x51)
        _ = writeVCP(service: service, command: 0xF4, value: altCode, retries: 2, dataAddress: 0x50)
        
        // 2. Send standard VESA VCP 0x60
        let vesaSuccess = writeVCP(service: service, command: DDCVCP.inputSource, value: vesaCode, retries: 2, dataAddress: 0x51)
        
        // 3. Fallback bridge via BetterDisplay CLI if installed on system
        if FileManager.default.fileExists(atPath: "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay")
            task.arguments = ["set", "-namelike=LG", "-ddcAlt=\(altCode)", "-vcp=inputSelectAlt"]
            try? task.run()
        }
        
        return vesaSuccess
    }
    
    /// Reads a DDC/CI VCP value (current value and max value)
    public func readVCP(service: IOAVServiceRef, command: UInt8, retries: Int = 4) -> (current: UInt16, max: UInt16)? {
        let send: [UInt8] = [command] // DDC Get VCP Request payload is just the command
        let dataAddress = ddcDataAddress
        
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let initialChk: UInt8 = (ddc7BitAddress << 1)
        packet[packet.count - 1] = checksum(chk: initialChk, data: &packet, start: 0, end: packet.count - 2)
        
        var reply: [UInt8] = [UInt8](repeating: 0, count: 11)
        
        for _ in 1...(retries + 1) {
            usleep(10000)
            let writeStatus = IOAVServiceWriteI2C(
                service,
                UInt32(ddc7BitAddress),
                UInt32(dataAddress),
                &packet,
                UInt32(packet.count)
            )
            guard writeStatus == kIOReturnSuccess else {
                usleep(25000)
                continue
            }
            
            // Wait for monitor to process command
            usleep(40000)
            
            let readStatus = IOAVServiceReadI2C(
                service,
                UInt32(ddc7BitAddress),
                0,
                &reply,
                UInt32(reply.count)
            )
            if readStatus == kIOReturnSuccess {
                let computedChk = checksum(chk: 0x50, data: &reply, start: 0, end: reply.count - 2)
                if computedChk == reply[reply.count - 1] {
                    let maxVal = UInt16(reply[6]) * 256 + UInt16(reply[7])
                    let curVal = UInt16(reply[8]) * 256 + UInt16(reply[9])
                    return (current: curVal, max: maxVal)
                }
            }
            usleep(25000)
        }
        return nil
    }
    
    // MARK: - Convenience Helpers
    
    public func setBrightness(service: IOAVServiceRef, value: Int) -> Bool {
        let clamped = UInt16(max(0, min(100, value)))
        return writeVCP(service: service, command: DDCVCP.brightness, value: clamped)
    }
    
    public func getBrightness(service: IOAVServiceRef) -> (current: Int, max: Int)? {
        if let res = readVCP(service: service, command: DDCVCP.brightness) {
            return (current: Int(res.current), max: Int(res.max))
        }
        return nil
    }
    
    public func setInputSource(service: IOAVServiceRef, value: UInt16) -> Bool {
        return writeVCP(service: service, command: DDCVCP.inputSource, value: value)
    }
    
    public func getInputSource(service: IOAVServiceRef) -> (current: UInt16, max: UInt16)? {
        return readVCP(service: service, command: DDCVCP.inputSource)
    }
    
    public func setVolume(service: IOAVServiceRef, value: Int) -> Bool {
        let clamped = UInt16(max(0, min(100, value)))
        return writeVCP(service: service, command: DDCVCP.audioVolume, value: clamped)
    }
    
    public func setPowerStandby(service: IOAVServiceRef) -> Bool {
        return writeVCP(service: service, command: DDCVCP.powerMode, value: 0x04)
    }
}
