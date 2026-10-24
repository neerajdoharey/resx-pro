import AppKit
import CoreGraphics

public struct ScreenDetector {
    /// Returns the active display ID under the mouse pointer, resolving Cocoa NSScreen coordinates
    /// first and falling back to Quartz display coordinates.
    public static func activeDisplayID() -> CGDirectDisplayID {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLocation, screen.frame, false) {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    return screenNumber
                }
            }
        }
        if let display = displayUnderPointer() {
            return display
        }
        return CGMainDisplayID()
    }

    /// Resolve the pointer in Quartz coordinates when the key event arrives.
    public static func displayUnderPointer() -> CGDirectDisplayID? {
        guard let position = CGEvent(source: nil)?.location else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(position, 1, &display, &count) == .success,
              count >= 1 else { return nil }
        return display
    }

    /// Returns the CGDirectDisplayID of the display currently under the mouse pointer
    public static func getDisplayUnderMouse() -> CGDirectDisplayID {
        let mouseLocation = NSEvent.mouseLocation
        
        for screen in NSScreen.screens {
            if NSMouseInRect(mouseLocation, screen.frame, false) {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    return screenNumber
                }
            }
        }
        return CGMainDisplayID()
    }
    
    /// Returns the NSScreen instance currently containing the mouse cursor
    public static func getScreenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
    
    /// Checks if a display is Apple's built-in laptop screen
    public static func isBuiltinDisplay(displayID: CGDirectDisplayID) -> Bool {
        return CGDisplayIsBuiltin(displayID) != 0
    }
}
