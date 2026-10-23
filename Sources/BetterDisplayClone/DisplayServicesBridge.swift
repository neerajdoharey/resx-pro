import Foundation
import CoreGraphics

public final class DisplayServicesBridge: @unchecked Sendable {
    public static let shared = DisplayServicesBridge()
    
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    
    private var setBrightnessPtr: SetBrightnessFunc?
    private var getBrightnessPtr: GetBrightnessFunc?
    
    public init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightnessPtr = unsafeBitCast(setSym, to: SetBrightnessFunc.self)
            }
            if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightnessPtr = unsafeBitCast(getSym, to: GetBrightnessFunc.self)
            }
        }
    }
    
    public func setBrightness(displayID: CGDirectDisplayID, brightness: Float) -> Bool {
        guard let fn = setBrightnessPtr else { return false }
        let clamped = max(0.0, min(1.0, brightness))
        return fn(displayID, clamped) == 0
    }
    
    public func getBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard let fn = getBrightnessPtr else { return nil }
        var val: Float = 0.0
        if fn(displayID, &val) == 0 {
            return val
        }
        return nil
    }
}
