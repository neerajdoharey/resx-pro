import SwiftUI
import AppKit

// MARK: - Apple-Style Pressable Button Style
public struct ApplePressableButtonStyle: ButtonStyle {
    var scale: CGFloat
    var opacity: CGFloat
    
    public init(scale: CGFloat = 0.96, opacity: CGFloat = 0.88) {
        self.scale = scale
        self.opacity = opacity
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? opacity : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Apple Keyboard Keycap Badge (⌥1, ⌥2)
public struct AppleKeycapBadge: View {
    let shortcut: String
    
    public init(_ shortcut: String) {
        self.shortcut = shortcut
    }
    
    public var body: some View {
        Text(shortcut)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.95))
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.20), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Interactive Menu Row Component
public struct MenuRowButton: View {
    let icon: String
    let title: String
    var action: (() -> Void)? = nil
    @State private var isHovered: Bool = false
    
    public init(icon: String, title: String, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.action = action
    }
    
    public var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 18, alignment: .center)
                
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.92))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplePressableButtonStyle(scale: 0.98, opacity: 0.85))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Custom BetterDisplay-Style Slider (Apple Fluid Physics)
public struct BDSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var tintColor: Color = .white
    var onEditingChanged: ((Double) -> Void)? = nil
    
    @State private var isDragging: Bool = false
    
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
            let thumbDiameter: CGFloat = isDragging ? 16.5 : 14.0
            
            ZStack(alignment: .leading) {
                // Background Track (Glass Inset)
                Capsule()
                    .fill(Color.black.opacity(0.50))
                    .frame(height: 5)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
                
                // Active Fill (Vibrant Gradient)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tintColor.opacity(0.85), tintColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(5, fillWidth), height: 5)
                
                // Physical Direct Manipulation Thumb Knob
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isDragging ? 0.35 : 0.0), lineWidth: 3)
                            .scaleEffect(isDragging ? 1.25 : 1.0)
                            .opacity(isDragging ? 1.0 : 0.0)
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 2, x: 0, y: 1.5)
                    .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)
                    .offset(x: max(0, min(totalWidth - thumbDiameter, fillWidth - (thumbDiameter / 2.0))))
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isDragging)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                        }
                        
                        let locationX = max(0, min(totalWidth, gesture.location.x))
                        let newRatio = Double(locationX / totalWidth)
                        let rawVal = range.lowerBound + newRatio * (range.upperBound - range.lowerBound)
                        let stepped = (rawVal / step).rounded() * step
                        let clamped = max(range.lowerBound, min(range.upperBound, stepped))
                        
                        // Boundary haptic feedback on edge collision
                        if (clamped == range.lowerBound || clamped == range.upperBound) && self.value != clamped {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        }
                        
                        self.value = clamped
                        onEditingChanged?(clamped)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - Main Menu Bar View (ResX Pro)
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
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
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
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            proxy.scrollTo("footerBar", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                displayManager.refreshInputState()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .frame(width: 330)
        .frame(maxHeight: 700)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
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
                    .foregroundColor(.white.opacity(0.95))
                
                Text("Built-in Display")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                // Main Display (M) badge
                Text("M")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.14)], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                
                if isCursorHere {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.blue.opacity(0.8), radius: 3)
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
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
            )
            
            // Core Sliders (Always visible when collapsed)
            VStack(spacing: 9) {
                // Brightness (Combined)
                VStack(spacing: 4) {
                    HStack {
                        Text("Brightness (Combined)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.72))
                        Spacer()
                        Text("\(brightness)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.95))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                        
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
                            .foregroundColor(.white.opacity(0.72))
                        Spacer()
                        let resText = builtinResolutions[min(Int(builtinResolutionIndex), builtinResolutions.count - 1)]
                        Text(resText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.95))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                        
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
                        MenuRowButton(icon: "rectangle.inset.filled", title: "Display Mode")
                        MenuRowButton(icon: "paintpalette", title: "Colour Mode")
                        MenuRowButton(icon: "rectangle.on.rectangle", title: "Mirror Display")
                        MenuRowButton(icon: "play.rectangle", title: "Stream Display")
                        MenuRowButton(icon: "pip", title: "Picture in Picture")
                        MenuRowButton(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "Move Display")
                        MenuRowButton(icon: "rotate.right", title: "Screen Rotation")
                        MenuRowButton(icon: "slider.horizontal.3", title: "Image Adjustments")
                        MenuRowButton(icon: "circle.lefthalf.filled", title: "Colour Profile")
                        MenuRowButton(icon: "shield", title: "Configuration Protection")
                        MenuRowButton(icon: "gearshape.2", title: "Manage Display")
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
                
                disclosureButton(expanded: $isBuiltinExpanded, title: "Built-in display")
            }
        }
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.16),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 2)
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
                    .foregroundColor(.white.opacity(0.95))
                
                Text(external?.name ?? "LG HDR 4K")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                if isCursorHere {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.blue.opacity(0.8), radius: 3)
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
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
            )
            
            // Sliders (Always visible when collapsed)
            VStack(spacing: 9) {
                // Brightness (Combined)
                VStack(spacing: 4) {
                    HStack {
                        Text("Brightness (Combined)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.72))
                        Spacer()
                        Text("\(brightness)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.95))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sun.max")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                        
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
                            .foregroundColor(.white.opacity(0.72))
                        Spacer()
                        let resText = externalResolutions[min(Int(externalResolutionIndex), externalResolutions.count - 1)]
                        Text(resText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.95))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                        
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
                            .foregroundColor(.white.opacity(0.72))
                        Spacer()
                        Text("\(volume)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.95))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.65))
                        
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
                            tintColor: .purple.opacity(0.85)
                        )
                    }
                }
                .padding(.horizontal, 12)
                
                // Expanded Details for LG Monitor
                if isExternalExpanded {
                    VStack(spacing: 2) {
                        MenuRowButton(icon: "rectangle.inset.filled", title: "Display Mode")
                        MenuRowButton(icon: "paintpalette", title: "Colour Mode")
                        MenuRowButton(icon: "rectangle.on.rectangle", title: "Mirror Display")
                        MenuRowButton(icon: "rotate.right", title: "Screen Rotation")
                        MenuRowButton(icon: "slider.horizontal.3", title: "Image Adjustments")
                        MenuRowButton(icon: "circle.lefthalf.filled", title: "Colour Profile")
                        MenuRowButton(icon: "gearshape.2", title: "Manage Display")
                    }
                    .padding(.top, 4)
                }
                
                disclosureButton(expanded: $isExternalExpanded, title: "External display")
            }
        }
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.16),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 2)
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
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.09))
                            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.07)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
            )
            
            // Port Selection Buttons: supported connectors are separate from device presence.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(displayManager.availableInputs) { input in
                    Button {
                        selectInput(input)
                    } label: {
                        inputButtonLabel(input)
                    }
                    .buttonStyle(ApplePressableButtonStyle(scale: 0.97))
                    .disabled(displayManager.isSwitchingInput)
                    .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
                }
            }
            Text(displayManager.inputProfileName != nil
                 ? "LG 32UN650-W · HDMI 1, HDMI 2, DisplayPort. Device presence is not reported."
                 : "Gray means not selected; DDC cannot confirm attached device power.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)


            if let msg = displayManager.inputStatus ?? statusMessage {
                Text(msg)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.16),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - 4. Tools Section
    private var toolsSection: some View {
        VStack(spacing: 0) {
            // Header Pill: (...) Tools
            Button(action: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isToolsExpanded = false
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.90))
                    
                    Text("Tools")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                )
            }
            .buttonStyle(ApplePressableButtonStyle(scale: 0.97))
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 2)
            
            // Menu Items List
            VStack(spacing: 2) {
                MenuRowButton(icon: "display.2", title: "Displays And Virtual Screens")
                MenuRowButton(icon: "arrow.uturn.right.square", title: "Video Filter Window")
                MenuRowButton(icon: "circle.circle", title: "System Colours")
                
                MenuRowButton(icon: "arrow.down.circle", title: "Check for Updates") {
                    displayManager.refreshDisplays()
                }
                
                MenuRowButton(icon: "xmark.circle", title: "Quit ResX Pro") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.16),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 2)
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
                        .foregroundColor(isAccessibilityGranted ? .green : .white.opacity(0.85))
                    
                    Text(isAccessibilityGranted ? "Permissions Active" : "Set Up Permissions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                )
            }
            .buttonStyle(ApplePressableButtonStyle(scale: 0.96))
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
                    )
            }
            .buttonStyle(ApplePressableButtonStyle(scale: 0.94))
            
            Button(action: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isToolsExpanded.toggle()
                }
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(isToolsExpanded ? 1.0 : 0.75))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isToolsExpanded ?
                                        [Color.white.opacity(0.26), Color.white.opacity(0.16)] :
                                        [Color.white.opacity(0.10), Color.white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(isToolsExpanded ? 0.3 : 0.12), lineWidth: 0.6)
                            )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(ApplePressableButtonStyle(scale: 0.94))
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
    
    // MARK: - Helper Views
    
    private func actionRow(icon: String, title: String, isOn: Binding<Bool>, iconColor: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(iconColor)
                .frame(width: 18, alignment: .center)
            
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private func switchInput(port: String, displayName: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            statusMessage = "Switching monitor to \(displayName)..."
        }
        let success = displayManager.switchInput(portName: port)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            if success {
                statusMessage = "✅ Switched to \(displayName)!"
            } else {
                statusMessage = "⚠️ Command sent (monitor should switch to \(displayName))"
            }
        }
    }

    private func disclosureButton(expanded: Binding<Bool>, title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(expanded.wrappedValue ? "Less" : "More")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
        }
        .buttonStyle(ApplePressableButtonStyle(scale: 0.98))
        .accessibilityLabel("\(expanded.wrappedValue ? "Collapse" : "Expand") \(title) details")
        .onHover { if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
    }

    private func iconForInput(_ input: DisplayInput) -> String {
        switch input.kind {
        case .hdmi: return "tv.fill"
        case .displayPort: return "display"
        case .usb: return "cable.connector"
        case .other: return "display"
        }
    }

    private func inputButtonLabel(_ input: DisplayInput) -> some View {
        let current = displayManager.displays.first(where: { !$0.isBuiltin })?.inputSource
        let selected = current == input.code
        let shade = displayManager.displays.first(where: { !$0.isBuiltin })?.brightness ?? 50
        let title = input.name
        return HStack(spacing: 7) {
            Image(systemName: iconForInput(input))
                .foregroundStyle(selected ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(selected ? (shade <= -200 ? "Selected · Mac blacked out" : "Selected") : (current == nil ? "Status unknown" : "Not selected"))
                    .font(.system(size: 9)).foregroundStyle(selected ? Color.green : Color.secondary)
            }
            Spacer(minLength: 0)
            if selected { Image(systemName: shade <= -200 ? "moon.fill" : "checkmark.circle.fill").foregroundStyle(shade <= -200 ? .orange : .green) }
        }
        .foregroundStyle(.white.opacity(selected ? 1 : 0.72))
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.green.opacity(0.16) : Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.green.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func selectInput(_ input: DisplayInput) {
        guard let external = displayManager.displays.first(where: { !$0.isBuiltin }) else { return }
        if external.inputSource == input.code {
            if external.brightness <= -200 { displayManager.wakeSleepingDisplays(targetDisplayID: external.id) }
            else { displayManager.setBrightness(displayID: external.id, value: -200) }
        } else {
            displayManager.switchInputAsync(input: input)
        }
    }
}
