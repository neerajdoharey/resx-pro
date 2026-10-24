import Testing
@testable import BetterDisplayClone

private func reply(command: UInt8 = 0x10, status: UInt8 = 0, maximum: UInt16 = 100, current: UInt16 = 42) -> [UInt8] {
    var bytes: [UInt8] = [0x6E, 0x88, 0x02, status, command, 0,
                          UInt8(maximum >> 8), UInt8(maximum & 255), UInt8(current >> 8), UInt8(current & 255)]
    bytes.append(bytes.reduce(UInt8(0x50), ^))
    return bytes
}

@Test func recoveryRejectsUnsupportedAndStaleDDCReplies() {
    #expect(DDCService.parseVCPReply(reply(status: 1), command: 0x10) == nil)
    #expect(DDCService.parseVCPReply(reply(command: 0x60), command: 0x10) == nil)
    #expect(DDCService.parseVCPReply([], command: 0x10) == nil)
    #expect(DDCService.parseVCPReply(reply(maximum: 0, current: 0), command: 0x10) == nil)
    #expect(DDCService.parseVCPReply(reply(maximum: 50, current: 75), command: 0x10) == nil)
    var corrupt = reply()
    corrupt[8] = 5
    #expect(DDCService.parseVCPReply(corrupt, command: 0x10) == nil)
    var wrongHeader = reply()
    wrongHeader[0] = 0
    wrongHeader[10] = wrongHeader.prefix(10).reduce(UInt8(0x50), ^)
    #expect(DDCService.parseVCPReply(wrongHeader, command: 0x10) == nil)
}

@Test func recoveryDecodesFullWidthDDCValues() {
    let value = DDCService.parseVCPReply(reply(maximum: 1000, current: 420), command: 0x10)
    #expect(value?.current == 420)
    #expect(value?.max == 1000)
}

@Test @MainActor func recoveryPreservesSoftwareStateAcrossHardwareRefresh() {
    #expect(DisplayManager.reconciledBrightness(previous: -200, hardware: 0) == -200)
    #expect(DisplayManager.reconciledBrightness(previous: -50, hardware: 0) == -50)
    #expect(DisplayManager.reconciledBrightness(previous: 75, hardware: 42) == 42)
    #expect(DisplayManager.reconciledBrightness(previous: nil, hardware: 42) == 42)
}

@Test func recoveryParsesNestedCapabilitiesAndWholeInputCodes() {
    let inputs = DDCService.parseAvailableInputs("(prot(monitor)model(Test)vcp(10 12 14(01 02) 60(0F 11 12 D0) D6(01 04)))")
    #expect(inputs.map(\.code) == [0x0F, 0x11, 0x12, 0xD0])
    #expect(DDCService.parseAvailableInputs("(vcp(10 12))").isEmpty)
    #expect(DDCService.parseAvailableInputs("(vcp(60(11 12)").isEmpty)
}

@Test func recoveryValidatesCapabilityFragmentOffsetsAndChecksum() {
    let payload = Array("(vcp(60(".utf8)
    var packet: [UInt8] = [0x6E, UInt8(0x80 | (payload.count + 3)), 0xE3, 0, 32] + payload
    packet.append(packet.reduce(UInt8(0x50), ^))
    #expect(DDCService.parseCapabilitiesReply(packet, offset: 32) == payload)
    #expect(DDCService.parseCapabilitiesReply(packet, offset: 0) == nil)
    packet[5] ^= 1
    #expect(DDCService.parseCapabilitiesReply(packet, offset: 32) == nil)
}

@Test @MainActor func recoveryScopesKnownMonitorProfileToConfirmedUnit() {
    #expect(DisplayManager.knownMonitorName(vendor: 0x1E6D, product: 0x774F, serial: 0x1FE19) == "LG 32UN650-W")
    #expect(DisplayManager.knownMonitorName(vendor: 0x1E6D, product: 0x774F, serial: 123) == nil)
    #expect(DisplayManager.knownMonitorName(vendor: 0x610, product: 0x774F, serial: 0x1FE19) == nil)
    #expect(DisplayManager.standardInputs.map(\.code) == [0x11, 0x12, 0x0F])
}
