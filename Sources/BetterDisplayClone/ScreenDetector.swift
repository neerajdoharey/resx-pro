import AppKit
import CoreGraphics

public struct ScreenDetector {
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
