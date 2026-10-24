import Testing
import CoreGraphics
@testable import BetterDisplayClone

@Test func testActiveDisplayIDReturnsValidDisplay() async throws {
    let activeID = ScreenDetector.activeDisplayID()
    #expect(activeID != 0)
}

@Test func testDisplayManagerBrightnessReachesZero() async throws {
    await MainActor.run {
        let manager = DisplayManager.shared
        for display in manager.displays {
            let initial = display.brightness
            manager.setBrightness(displayID: display.id, value: 0)
            let current = manager.displays.first(where: { $0.id == display.id })?.brightness
            #expect(current == 0)

            // Test negative combined dimming range
            manager.setBrightness(displayID: display.id, value: -50)
            let currentNeg = manager.displays.first(where: { $0.id == display.id })?.brightness
            #expect(currentNeg == -50)

            manager.setBrightness(displayID: display.id, value: -200)
            let currentMin = manager.displays.first(where: { $0.id == display.id })?.brightness
            #expect(currentMin == -200)
            #expect(manager.hasSleepingDisplays == true)

            // Test waking from blackout (-200%) via Brightness UP
            manager.adjustBrightnessDebounced(displayID: display.id, delta: 5)
            let currentWoken = manager.displays.first(where: { $0.id == display.id })?.brightness
            #expect(currentWoken == 15) // Entered blackout from software dimming, so restore the visible minimum.
            #expect(manager.hasSleepingDisplays == false)

            // Restore initial brightness
            manager.setBrightness(displayID: display.id, value: initial)
        }
    }
}
