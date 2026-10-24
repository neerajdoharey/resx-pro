import AppKit
import CoreGraphics

@MainActor
public final class ShadeManager {
    public static let shared = ShadeManager()

    private var shadePanels: [CGDirectDisplayID: NSPanel] = [:]

    public init() {}

    /// Sets the software dimming overlay alpha for a given display.
    /// - Parameters:
    ///   - displayID: Target CGDirectDisplayID
    ///   - alpha: Opacity between 0.0 (transparent / off) and 1.0 (pitch black)
    public func setShade(displayID: CGDirectDisplayID, alpha: CGFloat) {
        let clampedAlpha = max(0.0, min(1.0, alpha))
        // Clearing must work even after the screen disappeared or changed its ID.
        if clampedAlpha <= 0.001 {
            shadePanels.removeValue(forKey: displayID)?.orderOut(nil)
            return
        }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }) else { return }

        let panel: NSPanel
        if let existing = shadePanels[displayID] {
            panel = existing
        } else {
            let p = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .black
            p.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)))
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.ignoresMouseEvents = true
            p.hasShadow = false
            shadePanels[displayID] = p
            panel = p
        }

        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = clampedAlpha
        panel.orderFrontRegardless()
    }

    /// Clears all active shades across all displays
    public func removeAllShades() {
        for (_, panel) in shadePanels {
            panel.orderOut(nil)
        }
        shadePanels.removeAll()
    }
}
