import AppKit
import SwiftUI

@MainActor
public final class OSDManager {
    public static let shared = OSDManager()
    
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var hostingView: NSHostingView<OSDView>?
    
    public init() {
        setupPanel()
    }
    
    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 210),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hasShadow = true
        p.ignoresMouseEvents = true
        self.panel = p
    }
    
    public func show(displayName: String, value: Int, icon: String, screen: NSScreen?) {
        guard let panel = self.panel else { return }
        let targetScreen = screen ?? ScreenDetector.getScreenUnderMouse() ?? NSScreen.main
        
        let osdView = OSDView(displayName: displayName, value: value, icon: icon)
        if hostingView == nil {
            let hv = NSHostingView(rootView: osdView)
            panel.contentView = hv
            self.hostingView = hv
        } else {
            hostingView?.rootView = osdView
        }
        
        if let s = targetScreen {
            let screenRect = s.frame
            let x = screenRect.origin.x + (screenRect.width - 220) / 2
            let y = screenRect.origin.y + 140 // Native macOS HUD position: lower-center
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
        
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fadeOut()
            }
        }
    }
    
    public func showStatus(title: String, subtitle: String, icon: String, screen: NSScreen? = nil) {
        guard let panel = self.panel else { return }
        let targetScreen = screen ?? ScreenDetector.getScreenUnderMouse() ?? NSScreen.main
        
        let statusView = OSDStatusView(title: title, subtitle: subtitle, icon: icon)
        panel.contentView = NSHostingView(rootView: statusView)
        self.hostingView = nil
        
        if let s = targetScreen {
            let screenRect = s.frame
            let x = screenRect.origin.x + (screenRect.width - 220) / 2
            let y = screenRect.origin.y + 140
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
        
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fadeOut()
            }
        }
    }
    
    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.panel?.animator().alphaValue = 0.0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.panel?.orderOut(nil)
            }
        }
    }
}

public struct OSDView: View {
    let displayName: String
    let value: Int
    let icon: String
    
    public var body: some View {
        VStack(spacing: 14) {
            Text(displayName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            
            Image(systemName: icon)
                .font(.system(size: 54, weight: .regular))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(value) / 100.0)))
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 16)
            
            Text("\(value)%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.vertical, 18)
        .frame(width: 200, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
    }
}

public struct OSDStatusView: View {
    let title: String
    let subtitle: String
    let icon: String
    
    public var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            
            Image(systemName: icon)
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            Text(subtitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(width: 200, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
    }
}
