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

public struct DisplayInput: Identifiable, Sendable {
    public let code: UInt16
    public let name: String
    public let kind: Kind

    public var id: UInt16 { code }

    public enum Kind: Sendable {
        case hdmi, displayPort, usb, other
    }

    public static func fromVCPCode(_ code: UInt16) -> DisplayInput {
        switch code {
        case 0x01: DisplayInput(code: code, name: "VGA", kind: .other)
        case 0x02: DisplayInput(code: code, name: "S-Video", kind: .other)
        case 0x03: DisplayInput(code: code, name: "Composite", kind: .other)
        case 0x04: DisplayInput(code: code, name: "Component", kind: .other)
        case 0x05: DisplayInput(code: code, name: "DVI", kind: .other)
        case 0x0F: DisplayInput(code: code, name: "DisplayPort", kind: .displayPort)
        case 0x10: DisplayInput(code: code, name: "DisplayPort 2", kind: .displayPort)
        case 0x11: DisplayInput(code: code, name: "HDMI 1", kind: .hdmi)
        case 0x12: DisplayInput(code: code, name: "HDMI 2", kind: .hdmi)
        case 0x13: DisplayInput(code: code, name: "HDMI 3", kind: .hdmi)
        case 0x14: DisplayInput(code: code, name: "HDMI 4", kind: .hdmi)
        case 0xD0: DisplayInput(code: code, name: "USB-C", kind: .usb)
        default: DisplayInput(code: code, name: String(format: "Input 0x%02X", code), kind: .other)
        }
    }
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

    private let busLock = NSRecursiveLock()

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

    private func ddcPacket(payload: [UInt8], dataAddress: UInt8 = 0x51) -> [UInt8] {
        var packet = [UInt8(0x80 | payload.count)] + payload + [UInt8(0)]
        let initialChk: UInt8 = (ddc7BitAddress << 1) ^ dataAddress
        packet[packet.count - 1] = checksum(chk: initialChk, data: &packet, start: 0, end: packet.count - 2)
        return packet
    }

    /// Writes a DDC/CI VCP command to an external display
    @discardableResult
    public func writeVCP(service: IOAVServiceRef, command: UInt8, value: UInt16, retries: Int = 3, dataAddress: UInt8 = 0x51) -> Bool {
        busLock.lock()
        defer { busLock.unlock() }
        // Set VCP payload: control byte 0x03, feature code, and 16-bit value.
        let payload: [UInt8] = [0x03, command, UInt8(value >> 8), UInt8(value & 0xFF)]
        var packet = ddcPacket(payload: payload, dataAddress: dataAddress)

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
        busLock.lock()
        defer { busLock.unlock() }
        let payload: [UInt8] = [0x01, command] // Get VCP control byte + feature code
        let dataAddress = ddcDataAddress
        var packet = ddcPacket(payload: payload)

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
                // If reply is completely zeroed, monitor/bus does not return DDC read replies.
                // Fail immediately rather than looping through retries and lagging.
                if reply.allSatisfy({ $0 == 0 }) {
                    return nil
                }
                if let value = Self.parseVCPReply(reply, command: command) {
                    return value
                }
            }
            usleep(25000)
        }
        return nil
    }

    /// Reject unsupported features, stale replies and malformed packets before using their range.
    static func parseVCPReply(_ reply: [UInt8], command: UInt8) -> (current: UInt16, max: UInt16)? {
        guard reply.count == 11, reply[0] == 0x6E, reply[1] == 0x88,
              reply[2] == 0x02, reply[3] == 0, reply[4] == command,
              reply.reduce(UInt8(0x50), ^) == 0 else { return nil }
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        if command == DDCVCP.brightness && (maximum == 0 || current > maximum) { return nil }
        return (current, maximum)
    }

    // MARK: - Convenience Helpers

    private let ddcQueue = DispatchQueue(label: "com.resxpro.ddcqueue", qos: .userInitiated)
    private var pendingBrightnessWrites: [ObjectIdentifier: (service: IOAVServiceRef, value: Int, completion: (@Sendable (Bool, Int?) -> Void)?)] = [:]
    private var cachedMaxBrightness: [ObjectIdentifier: UInt16] = [:]
    private var isProcessingBrightness = false
    private let brightnessLock = NSLock()

    public func maxBrightness(for service: IOAVServiceRef) -> UInt16 {
        busLock.lock()
        defer { busLock.unlock() }
        let key = ObjectIdentifier(service)
        if let cached = cachedMaxBrightness[key] {
            return cached
        }
        if let res = readVCP(service: service, command: DDCVCP.brightness), res.max > 0 {
            cachedMaxBrightness[key] = res.max
            return res.max
        }
        return 100
    }

    @discardableResult
    public func setBrightness(service: IOAVServiceRef, value: Int) -> Bool {
        let clamped = max(0, min(100, value))
        let maximum = maxBrightness(for: service)
        let rawValue = UInt16((Double(maximum) * Double(clamped) / 100.0).rounded())
        return writeVCP(service: service, command: DDCVCP.brightness, value: rawValue)
    }

    /// Asynchronously writes brightness to external monitor with request coalescing,
    /// ensuring the UI and event loop never freeze and the bus is never overwhelmed.
    public func setBrightnessAsync(service: IOAVServiceRef, value: Int, completion: (@Sendable (Bool, Int?) -> Void)? = nil) {
        let key = ObjectIdentifier(service)
        brightnessLock.lock()
        pendingBrightnessWrites[key] = (service, value, completion)
        let shouldStart = !isProcessingBrightness
        if shouldStart {
            isProcessingBrightness = true
        }
        brightnessLock.unlock()

        if shouldStart {
            ddcQueue.async { [weak self] in
                self?.processPendingBrightness()
            }
        }
    }

    private func processPendingBrightness() {
        while true {
            brightnessLock.lock()
            guard let (key, item) = pendingBrightnessWrites.first else {
                isProcessingBrightness = false
                brightnessLock.unlock()
                break
            }
            pendingBrightnessWrites.removeValue(forKey: key)
            brightnessLock.unlock()

            let success = setBrightness(service: item.service, value: item.value)
            let actual = success ? getBrightness(service: item.service)?.current : nil
            item.completion?(success, actual)
        }
    }

    public func getBrightness(service: IOAVServiceRef) -> (current: Int, max: Int)? {
        if let res = readVCP(service: service, command: DDCVCP.brightness) {
            guard res.max > 0 else { return nil }
            let percentage = Int((Double(res.current) * 100 / Double(res.max)).rounded())
            return (current: max(0, min(100, percentage)), max: 100)
        }
        return nil
    }

    public func setInputSource(service: IOAVServiceRef, value: UInt16) -> Bool {
        return writeVCP(service: service, command: DDCVCP.inputSource, value: value)
    }

    public func getInputSource(service: IOAVServiceRef) -> (current: UInt16, max: UInt16)? {
        guard let value = readVCP(service: service, command: DDCVCP.inputSource), value.current != 0 else { return nil }
        return value
    }

    /// Returns input codes declared by the monitor's standard VCP capabilities reply.
    public func getAvailableInputs(service: IOAVServiceRef) -> [DisplayInput] {
        guard let capabilities = readCapabilities(service: service) else { return [] }
        return Self.parseAvailableInputs(capabilities)
    }

    static func parseAvailableInputs(_ capabilities: String) -> [DisplayInput] {
        guard let start = capabilities.range(of: "vcp(", options: .caseInsensitive) else { return [] }
        var depth = 1
        var end = start.upperBound
        while end < capabilities.endIndex && depth > 0 {
            if capabilities[end] == "(" { depth += 1 }
            if capabilities[end] == ")" { depth -= 1 }
            if depth > 0 { end = capabilities.index(after: end) }
        }
        guard depth == 0 else { return [] }
        let vcp = String(capabilities[start.upperBound..<end])
        let pattern = #"(?:^|\s)60\s*\(([^()]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: vcp, range: NSRange(vcp.startIndex..., in: vcp)),
              let range = Range(match.range(at: 1), in: vcp) else { return [] }
        let codes = Set(vcp[range].split(whereSeparator: { $0.isWhitespace }).compactMap { UInt16($0, radix: 16) })
        return codes.sorted().map(DisplayInput.fromVCPCode)
    }

    static func parseCapabilitiesReply(_ reply: [UInt8], offset: Int) -> [UInt8]? {
        guard reply.count >= 6, reply[0] == 0x6E, reply[1] & 0x80 != 0 else { return nil }
        let length = Int(reply[1] & 0x7F)
        guard length >= 3, length + 3 <= reply.count, reply[2] == 0xE3,
              Int(reply[3]) * 256 + Int(reply[4]) == offset,
              reply.prefix(length + 3).reduce(UInt8(0x50), ^) == 0 else { return nil }
        return Array(reply[5..<(length + 2)])
    }

    private func readCapabilities(service: IOAVServiceRef) -> String? {
        busLock.lock()
        defer { busLock.unlock() }
        var bytes: [UInt8] = []
        while bytes.count < 4096 {
            let offset = bytes.count
            var packet = ddcPacket(payload: [0xF3, UInt8(offset >> 8), UInt8(offset & 255)])
            usleep(15000)
            guard IOAVServiceWriteI2C(service, UInt32(ddc7BitAddress), UInt32(ddcDataAddress), &packet, UInt32(packet.count)) == kIOReturnSuccess else { return nil }
            usleep(50000)
            var reply = [UInt8](repeating: 0, count: 38)
            guard IOAVServiceReadI2C(service, UInt32(ddc7BitAddress), 0, &reply, UInt32(reply.count)) == kIOReturnSuccess,
                  let chunk = Self.parseCapabilitiesReply(reply, offset: offset) else { return nil }
            if chunk.isEmpty || chunk.contains(0) {
                bytes.append(contentsOf: chunk.prefix { $0 != 0 })
                return String(bytes: bytes, encoding: .ascii)
            }
            bytes.append(contentsOf: chunk)
        }
        return nil
    }

    public func setVolume(service: IOAVServiceRef, value: Int) -> Bool {
        let clamped = UInt16(max(0, min(100, value)))
        return writeVCP(service: service, command: DDCVCP.audioVolume, value: clamped)
    }

    public func setPowerStandby(service: IOAVServiceRef) -> Bool {
        return writeVCP(service: service, command: DDCVCP.powerMode, value: 0x04, retries: 3)
    }

    public func setPowerOff(service: IOAVServiceRef) -> Bool {
        return writeVCP(service: service, command: DDCVCP.powerMode, value: 0x05, retries: 3)
    }

    public func setPowerOn(service: IOAVServiceRef) -> Bool {
        return writeVCP(service: service, command: DDCVCP.powerMode, value: 0x01, retries: 3)
    }
}
