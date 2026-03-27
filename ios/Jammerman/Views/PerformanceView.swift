// Jammerman — Main Performance View
// Full-screen camera with instrument toggles, mode HUD, synth panel

import SwiftUI

struct PerformanceView: View {
    @ObservedObject var coordinator: TrackingCoordinator
    @State private var showSynthPanel = false
    @State private var selectedTab = "perform"
    @State private var volumeChannel: String? = nil
    @State private var volumeSliderValue: Float = 0

    var body: some View {
        ZStack {
            // Full-screen camera
            Color.black.ignoresSafeArea()
            CameraPreview(session: coordinator.camera.captureSession)
                .ignoresSafeArea()

            // Mode HUD (top center)
            VStack {
                modeHUD.padding(.top, 60)
                Spacer()
            }

            // Instrument toggles (right side)
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    instToggle("PAD", icon: "◈", channel: "pad", color: .purple)
                    instToggle("ARP", icon: "♪", channel: "arp", color: .cyan)
                    instToggle("ARP2", icon: "♫", channel: "arp2", color: .teal)
                    instToggle("MEL", icon: "🎵", channel: "melody", color: .green)
                    instToggle("BEAT", icon: "◉", channel: "beat", color: .orange)
                    instToggle("BIN", icon: "∿", channel: "binaural", color: .indigo)
                }
                .padding(.trailing, 12)
            }

            // Volume slider popup
            if let ch = volumeChannel {
                volumePopup(channel: ch)
            }

            // Bottom bar
            VStack {
                Spacer()
                bottomBar
            }

            // Synth panel (slides up from bottom)
            if showSynthPanel {
                synthPanel
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSynthPanel)
        .onAppear { coordinator.start() }
        .onDisappear { coordinator.stop() }
        .statusBarHidden()
    }

    // MARK: - Mode HUD

    private var modeHUD: some View {
        VStack(spacing: 4) {
            Text(coordinator.state.currentModeName.uppercased())
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)

            GeometryReader { geo in
                let pct = CGFloat((coordinator.state.lipCorner + 1) / 2)
                let barW: CGFloat = geo.size.width * 0.1
                let left = max(0, min(geo.size.width - barW, pct * geo.size.width - barW / 2))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.1))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: barW, height: 4)
                        .offset(x: left)
                }
            }
            .frame(width: 120, height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Instrument Toggle

    private func instToggle(_ label: String, icon: String, channel: String, color: Color) -> some View {
        let active = !coordinator.audioEngine.isMuted(channel)
        return Button {
            coordinator.toggleMute(channel)
        } label: {
            VStack(spacing: 2) {
                Text(icon).font(.system(size: 18))
                Text(label).font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .frame(width: 48, height: 48)
            .background(active ? color.opacity(0.8) : .white.opacity(0.08))
            .foregroundStyle(active ? .white : .white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? color : .white.opacity(0.1), lineWidth: 1))
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                volumeSliderValue = coordinator.audioEngine.channelVolumes[channel] ?? -10
                volumeChannel = channel
            }
        )
    }

    // MARK: - Volume Popup

    private func volumePopup(channel: String) -> some View {
        VStack(spacing: 8) {
            Text(channel.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Slider(value: $volumeSliderValue, in: -60...6)
                .tint(accentColor)
                .onChange(of: volumeSliderValue) { _, new in
                    coordinator.audioEngine.setChannelVolume(channel, db: new)
                }
            Text("\(Int(volumeSliderValue)) dB")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Button("Done") { volumeChannel = nil }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accentColor)
        }
        .padding(16)
        .background(.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(width: 200)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Face/hand indicators
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.state.faceDetected ? .green : .red.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(coordinator.state.faceDetected ? "Face" : "No face")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))

                if coordinator.state.handPresent {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text(coordinator.state.handOpen ? "Open" : "Fist")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            // Settings button
            Button {
                showSynthPanel.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(8)
                    .background(.white.opacity(0.1))
                    .clipShape(Circle())
            }

            Text("v1.2.0")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
    }

    // MARK: - Synth Panel

    private var synthPanel: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    tabButton("Perform", id: "perform")
                    tabButton("Arp 1", id: "arp1")
                    tabButton("Arp 2", id: "arp2")
                    tabButton("Drums", id: "drums")
                    tabButton("Key", id: "key")
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)

            // Tab content
            ScrollView {
                switch selectedTab {
                case "perform": performTab
                case "arp1": arpTab(id: 1)
                case "arp2": arpTab(id: 2)
                case "drums": drumsTab
                case "key": keyTab
                default: performTab
                }
            }
            .frame(maxHeight: 300)
            .padding(.bottom, 30)
        }
        .background(.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, UIScreen.main.bounds.height * 0.5)
        .ignoresSafeArea()
        .onTapGesture {} // prevent tap-through
    }

    private func tabButton(_ title: String, id: String) -> some View {
        Button {
            selectedTab = id
        } label: {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == id ? .bold : .regular, design: .monospaced))
                .foregroundStyle(selectedTab == id ? accentColor : .white.opacity(0.5))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(selectedTab == id ? accentColor.opacity(0.15) : .clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Perform Tab

    private var performTab: some View {
        VStack(spacing: 16) {
            // BPM
            HStack {
                Text("BPM").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                Slider(value: Binding(
                    get: { coordinator.audioEngine.bpm },
                    set: { coordinator.audioEngine.setBPM($0) }
                ), in: 40...200)
                .tint(accentColor)
                Text("\(Int(coordinator.audioEngine.bpm))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 35)
            }

            // Root note
            HStack {
                Text("Key").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                ForEach(0..<12, id: \.self) { i in
                    Button {
                        coordinator.state.rootOffset = i
                    } label: {
                        Text(JammermanConfig.noteNames[i])
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(coordinator.state.rootOffset == i ? .black : .white.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .background(coordinator.state.rootOffset == i ? accentColor : .white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // Binaural
            HStack {
                Text("Binaural Hz").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                Slider(value: Binding(
                    get: { coordinator.audioEngine.binauralBeatHz },
                    set: { coordinator.audioEngine.setBinauralBeatHz($0) }
                ), in: 0.5...12)
                .tint(.indigo)
                Text(String(format: "%.1f", coordinator.audioEngine.binauralBeatHz))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 30)
            }
        }
        .padding(16)
    }

    // MARK: - Arp Tab

    private func arpTab(id: Int) -> some View {
        let patterns = JammermanConfig.arpPatterns
        let noteValues = JammermanConfig.arpNoteValues
        let currentPattern = id == 1 ? coordinator.audioEngine.arpPattern : coordinator.audioEngine.arp2Pattern
        let currentNoteValue = id == 1 ? coordinator.audioEngine.arpNoteValue : coordinator.audioEngine.arp2NoteValue

        return VStack(spacing: 16) {
            // Pattern
            VStack(alignment: .leading, spacing: 6) {
                Text("Pattern").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(patterns, id: \.self) { p in
                        Button {
                            if id == 1 { coordinator.audioEngine.setArpPattern(p) }
                            else { coordinator.audioEngine.setArp2Pattern(p) }
                        } label: {
                            Text(p)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(currentPattern == p ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(currentPattern == p ? accentColor : .white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Note value
            VStack(alignment: .leading, spacing: 6) {
                Text("Note Value").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(noteValues, id: \.self) { v in
                        Button {
                            if id == 1 { coordinator.audioEngine.setArpNoteValue(v) }
                            else { coordinator.audioEngine.setArp2NoteValue(v) }
                        } label: {
                            Text(v)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(currentNoteValue == v ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(currentNoteValue == v ? accentColor : .white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Drums Tab

    private var drumsTab: some View {
        VStack(spacing: 12) {
            // Drum patterns
            let patternNames = ["Basic", "Funk", "Broken", "Minimal", "Trap", "Halftime"]
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(patternNames.enumerated()), id: \.offset) { i, name in
                        Button {
                            let patterns = JammermanConfig.chordDegrees // placeholder
                            // Apply drum pattern from config
                            applyDrumPreset(i)
                        } label: {
                            Text(name)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Step sequencer grid
            if coordinator.audioEngine.drumPattern.count >= 3 {
                drumGrid
            }
        }
        .padding(16)
    }

    private var drumGrid: some View {
        let drumNames = ["K", "S", "H"]
        let steps = coordinator.audioEngine.drumPattern[0].count
        let currentStep = coordinator.audioEngine.drumStep % max(steps, 1)

        return VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { drum in
                HStack(spacing: 2) {
                    Text(drumNames[drum])
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 16)
                    ForEach(0..<steps, id: \.self) { step in
                        let active = coordinator.audioEngine.drumPattern[drum][step] == 1
                        let isCurrent = step == currentStep && !coordinator.audioEngine.beatMuted
                        Rectangle()
                            .fill(active ? (isCurrent ? .white : .orange.opacity(0.8)) : (isCurrent ? .white.opacity(0.2) : .white.opacity(0.05)))
                            .frame(height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .onTapGesture {
                                coordinator.audioEngine.setDrumStep(drum: drum, step: step, active: !active)
                            }
                    }
                }
            }
        }
    }

    // MARK: - Key Tab

    private var keyTab: some View {
        VStack(spacing: 16) {
            // Scale override
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Scale Mode").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Toggle("Face Control", isOn: Binding(
                        get: { coordinator.state.extraScaleMode == nil },
                        set: { if $0 { coordinator.state.extraScaleMode = nil } }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                }

                let extraScales = Array(Scale.extra.keys.sorted())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                    ForEach(extraScales, id: \.self) { name in
                        Button {
                            coordinator.state.extraScaleMode = name
                        } label: {
                            Text(name)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(coordinator.state.extraScaleMode == name ? .black : .white.opacity(0.6))
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity)
                                .background(coordinator.state.extraScaleMode == name ? accentColor : .white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }

            // Freeze mode
            Toggle(isOn: $coordinator.state.modeFrozen) {
                Text("Freeze Mode").font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            }
            .toggleStyle(.switch)
            .tint(accentColor)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func applyDrumPreset(_ index: Int) {
        let patterns: [[[Int]]] = [
            // Basic
            [[1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0], [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]],
            // Funk
            [[1,0,0,0,0,0,1,0,1,0,0,0,0,0,1,0], [0,0,0,0,1,0,0,1,0,0,0,0,1,0,0,0], [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]],
            // Broken
            [[1,0,0,1,0,0,1,0,1,0,0,1,0,0,1,0], [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1], [1,0,1,0,1,0,1,0,1,0,1,1,1,0,1,0]],
            // Minimal
            [[1,0,0,0,0,0,0,0,1,0,1,0,0,0,0,0], [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], [0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0]],
            // Trap
            [[1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0], [0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0], [1,0,1,1,1,0,1,1,1,0,1,1,1,0,1,1]],
            // Halftime
            [[1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], [0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0], [1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]],
        ]
        guard index < patterns.count else { return }
        coordinator.audioEngine.setDrumPattern(patterns[index])
    }

    private var accentColor: Color {
        switch coordinator.state.currentModeName {
        case "lydian": return Color(red: 0.98, green: 0.57, blue: 0.24)
        case "ionian": return Color(red: 0.98, green: 0.75, blue: 0.14)
        case "mixolydian": return Color(red: 0.20, green: 0.83, blue: 0.60)
        case "dorian": return Color(red: 0.13, green: 0.83, blue: 0.93)
        case "aeolian": return Color(red: 0.51, green: 0.55, blue: 0.97)
        case "phrygian": return Color(red: 0.65, green: 0.55, blue: 0.98)
        default: return Color(red: 0.91, green: 0.66, blue: 0.28)
        }
    }
}
