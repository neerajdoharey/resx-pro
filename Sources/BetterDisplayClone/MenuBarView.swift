import SwiftUI
import AppKit

// MARK: - Custom BetterDisplay-Style Slider
public struct BDSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var tintColor: Color = .white
    var onEditingChanged: ((Double) -> Void)? = nil
    
    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...100,
        step: Double = 1,
        tintColor: Color = .white,
        onEditingChanged: ((Double) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.tintColor = tintColor
        self.onEditingChanged = onEditingChanged
    }
    
    public var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let percent = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let clampedPercent = max(0.0, min(1.0, percent))
            let fillWidth = totalWidth * clampedPercent
            
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .frame(height: 5)
                
                // Active Fill
                Capsule()
                    .fill(tintColor)
                    .frame(width: max(5, fillWidth), height: 5)
                
                // Thumb Knob
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                    .offset(x: max(0, min(totalWidth - 15, fillWidth - 7.5)))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let locationX = max(0, min(totalWidth, gesture.location.x))
                        let newRatio = Double(locationX / totalWidth)
                        let rawVal = range.lowerBound + newRatio * (range.upperBound - range.lowerBound)
                        let stepped = (rawVal / step).rounded() * step
                        let clamped = max(range.lowerBound, min(range.upperBound, stepped))
                        self.value = clamped
                        onEditingChanged?(clamped)
                    }
            )
        }
        .frame(height: 16)
    }
}

// MARK: - Main Menu Bar View (BetterDisplay Pro Clone)
public struct MenuBarView: View {
    @ObservedObject var displayManager = DisplayManager.shared
    
    // Default collapsed as requested
    @State private var isBuiltinExpanded: Bool = false
    @State private var isExternalExpanded: Bool = false
    @State private var isToolsExpanded: Bool = false
    
    // Toggle switch states
    @State private var isBuiltinEnabled: Bool = true
    @State private var isExternalEnabled: Bool = true
    
    // Feature toggles
    @State private var isHiDPIEnabled: Bool = true
    @State private var isAutoBrightnessEnabled: Bool = true
    
    // Resolution mock indices
    @State private var builtinResolutionIndex: Double = 2 // 1440x900
    @State private var externalResolutionIndex: Double = 2 // 1920x1080
    
    @State private var statusMessage: String? = nil
    @State private var isAccessibilityGranted: Bool = MediaKeyInterceptor.isAccessibilityTrusted()
    
    private let builtinResolutions = ["1024x640", "1280x800", "1440x900", "1680x1050", "2560x1600"]
    private let externalResolutions = ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
    
    public init() {}
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    // MARK: 1. Built-in Display Block (Separate)
                    builtinDisplayBlock
                    
                    // MARK: 2. LG HDR 4K External Display Block (Separate)
                    externalDisplayBlock
                    
                    // MARK: 3. Dedicated Video Input Switcher Block (Separate)
                    videoInputSwitcherBlock
                    
                    // MARK: 4. Tools Section (Visible only when expanded via ...)
                    if isToolsExpanded {
                        toolsSection
                            .id("toolsSection")
                    }
                    
                    // MARK: 5. Bottom Footer Bar
                    footerBar
                        .id("footerBar")
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .onChange(of: isToolsExpanded) { _, expanded in
                if expanded {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("footerBar", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(width: 330)
        .frame(maxHeight: 700)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 1. Built-in Display Block
    private var builtinDisplayBlock: some View {
        let builtin = displayManager.displays.first(where: { $0.isBuiltin })
        let brightness = builtin?.brightness ?? 91
        let isCursorHere = builtin?.id == displayManager.mouseDisplayID
        
        return VStack(spacing: 0) {
            // Header Pill
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Built-in Display")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                // Main Display (M) badge
                Text("M")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.white.opacity(0.2)))
                
                if isCursorHere {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
                
                Spacer()
                
                Toggle("", isOn: $isBuiltinEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .labelsHidden()
                    .scaleEffect(0.75)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            
            // Core Sliders (Always visible when collapsed)
            VStack(spacing: 9) {
                // Brightness (Combined)
                VStack(spacing: 4) {
                    HStack {
                        Text("Brightness (Combined)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(brightness)%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        BDSlider(
                            value: Binding(
                                get: { Double(brightness) },
                                set: { newVal in
                                    if let b = builtin {
                                        displayManager.setBrightness(displayID: b.id, value: Int(newVal), showHUD: false)
                                    }
                                }
                            ),
                            range: 0...100,
                            tintColor: .white
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Resolution Slider
                VStack(spacing: 4) {
                    HStack {
                        Text("Resolution")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        let resText = builtinResolutions[min(Int(builtinResolutionIndex), builtinResolutions.count - 1)]
                        Text(resText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        
                        BDSlider(
                            value: $builtinResolutionIndex,
                            range: 0...Double(builtinResolutions.count - 1),
                            step: 1,
                            tintColor: .white
                        )
                    }
                }
                .padding(.horizontal, 12)
                
                // Expanded Details
                if isBuiltinExpanded {
                    VStack(spacing: 2) {
                        menuRow(icon: "rectangle.inset.filled", title: "Display Mode")
                        menuRow(icon: "paintpalette", title: "Colour Mode")
                        menuRow(icon: "rectangle.on.rectangle", title: "Mirror Display")
                        menuRow(icon: "play.rectangle", title: "Stream Display")
                        menuRow(icon: "pip", title: "Picture in Picture")
                        menuRow(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "Move Display")
                        menuRow(icon: "rotate.right", title: "Screen Rotation")
                        menuRow(icon: "slider.horizontal.3", title: "Image Adjustments")
                        menuRow(icon: "circle.lefthalf.filled", title: "Colour Profile")
                        menuRow(icon: "shield", title: "Configuration Protection")
                        menuRow(icon: "gearshape.2", title: "Manage Display")
                    }
                    .padding(.top, 4)
                    
                    VStack(spacing: 6) {
                        actionRow(
                            icon: "sparkles",
                            title: "High Resolution (HiDPI)",
                            isOn: $isHiDPIEnabled,
                            iconColor: .blue
                        )
                        actionRow(
                            icon: "m.circle.fill",
                            title: "Set as Main Display",
                            isOn: .constant(true),
                            iconColor: .blue
                        )
                        actionRow(
                            icon: "a.circle.fill",
                            title: "Auto Brightness",
                            isOn: $isAutoBrightnessEnabled,
                            iconColor: .blue
                        )
                    }
                    .padding(.top, 4)
                }
                
                // Collapse/Expand Chevron
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBuiltinExpanded.toggle()
                    }
                }) {
                    Image(systemName: isBuiltinExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 2. LG HDR 4K External Display Block
    private var externalDisplayBlock: some View {
        let external = displayManager.displays.first(where: { !$0.isBuiltin })
        let brightness = external?.brightness ?? 80
        let volume = external?.volume ?? 40
        let isCursorHere = external?.id == displayManager.mouseDisplayID
        
        return VStack(spacing: 0) {
            // Header Pill
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Text(external?.name ?? "LG HDR 4K")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                if isCursorHere {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
                
                Spacer()
                
                Toggle("", isOn: $isExternalEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .labelsHidden()
                    .scaleEffect(0.75)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            
            // Sliders (Always visible when collapsed)
            VStack(spacing: 9) {
                // Brightness (Combined)
                VStack(spacing: 4) {
                    HStack {
                        Text("Brightness (Combined)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(brightness)%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        BDSlider(
                            value: Binding(
                                get: { Double(brightness) },
                                set: { newVal in
                                    if let ext = external {
                                        displayManager.setBrightness(displayID: ext.id, value: Int(newVal), showHUD: false)
                                    }
                                }
                            ),
                            range: 0...100,
                            tintColor: .white
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                
                // Resolution Slider
                VStack(spacing: 4) {
                    HStack {
                        Text("Resolution")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        let resText = externalResolutions[min(Int(externalResolutionIndex), externalResolutions.count - 1)]
                        Text(resText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        
                        BDSlider(
                            value: $externalResolutionIndex,
                            range: 0...Double(externalResolutions.count - 1),
                            step: 1,
                            tintColor: .white
                        )
                    }
                }
                .padding(.horizontal, 12)
                
                // Speaker Audio Volume Slider
                VStack(spacing: 4) {
                    HStack {
                        Text("Audio Volume (DDC)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(volume)%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        
                        BDSlider(
                            value: Binding(
                                get: { Double(volume) },
                                set: { newVal in
                                    if let ext = external {
                                        displayManager.setVolume(displayID: ext.id, value: Int(newVal), showHUD: false)
                                    }
                                }
                            ),
                            range: 0...100,
                            tintColor: .purple.opacity(0.8)
                        )
                    }
                }
                .padding(.horizontal, 12)
                
                // Expanded Details for LG Monitor
                if isExternalExpanded {
                    VStack(spacing: 2) {
                        menuRow(icon: "rectangle.inset.filled", title: "Display Mode")
                        menuRow(icon: "paintpalette", title: "Colour Mode")
                        menuRow(icon: "rectangle.on.rectangle", title: "Mirror Display")
                        menuRow(icon: "rotate.right", title: "Screen Rotation")
                        menuRow(icon: "slider.horizontal.3", title: "Image Adjustments")
                        menuRow(icon: "circle.lefthalf.filled", title: "Colour Profile")
                        menuRow(icon: "gearshape.2", title: "Manage Display")
                    }
                    .padding(.top, 4)
                }
                
                // Collapse/Expand Chevron
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExternalExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExternalExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 3. Dedicated Video Input Switcher Block (Separate)
    private var videoInputSwitcherBlock: some View {
        VStack(spacing: 8) {
            // Header Pill
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("Video Input Switcher")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("LG DDC/CI")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            
            // Port Selection Buttons
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                // PS5 Button (HDMI 2)
                Button(action: {
                    switchInput(port: "hdmi2", displayName: "PS5 (HDMI 2)")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.indigo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("PS5")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text("HDMI 2")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Text("⌥2")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.indigo.opacity(0.25))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.indigo.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Mac Button (Type-C)
                Button(action: {
                    switchInput(port: "mac", displayName: "Mac (Type-C)")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Mac M1")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Type-C")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Text("⌥1")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.25))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // HDMI 1 Button
                Button(action: {
                    switchInput(port: "hdmi1", displayName: "HDMI 1")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("HDMI 1")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Port 1")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // DisplayPort Button
                Button(action: {
                    switchInput(port: "dp", displayName: "DisplayPort")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "display")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DisplayPort")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Text("DP Port")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            
            if let msg = statusMessage {
                Text(msg)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 4. Tools Section
    private var toolsSection: some View {
        VStack(spacing: 0) {
            // Header Pill: (...) Tools
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isToolsExpanded = false
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Text("Tools")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 2)
            
            // Menu Items List
            VStack(spacing: 2) {
                menuRow(icon: "display.2", title: "Displays And Virtual Screens")
                menuRow(icon: "arrow.uturn.right.square", title: "Video Filter Window")
                menuRow(icon: "circle.circle", title: "System Colours")
                
                Button(action: {
                    displayManager.refreshDisplays()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 18, alignment: .center)
                        
                        Text("Check for Updates")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 18, alignment: .center)
                        
                        Text("Quit BetterDisplay")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 5. Footer Bar
    private var footerBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                MediaKeyInterceptor.requestAccessibilityPermissions()
                MediaKeyInterceptor.shared.start()
                isAccessibilityGranted = MediaKeyInterceptor.isAccessibilityTrusted()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "figure.stand")
                        .font(.system(size: 11))
                        .foregroundColor(isAccessibilityGranted ? .green : .white.opacity(0.8))
                    
                    Text(isAccessibilityGranted ? "Permissions Active" : "Set Up Permissions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isToolsExpanded.toggle()
                }
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(isToolsExpanded ? 1.0 : 0.7))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(Color.white.opacity(isToolsExpanded ? 0.22 : 0.08))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
    
    // MARK: - Helper Views
    
    private func menuRow(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 18, alignment: .center)
            
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
    
    private func actionRow(icon: String, title: String, isOn: Binding<Bool>, iconColor: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(iconColor)
                .frame(width: 18, alignment: .center)
            
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private func switchInput(port: String, displayName: String) {
        statusMessage = "Switching monitor to \(displayName)..."
        let success = displayManager.switchInput(portName: port)
        if success {
            statusMessage = "✅ Switched to \(displayName)!"
        } else {
            statusMessage = "⚠️ Command sent (monitor should switch to \(displayName))"
        }
    }
}
