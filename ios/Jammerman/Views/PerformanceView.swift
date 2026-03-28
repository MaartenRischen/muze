// Jammerman — Main Performance View
// Matches web app layout exactly per reference screenshots

import SwiftUI

struct PerformanceView: View {
    @ObservedObject var coordinator: TrackingCoordinator
    @State private var showSynthPanel = false
    @State private var showMixer = false
    @State private var showTutorial = false
    @State private var volumeChannel: String? = nil
    @State private var volumeSliderValue: Float = 0

    var body: some View {
        ZStack {
            // Full-screen camera
            Color.black.ignoresSafeArea()
            CameraPreview(session: coordinator.camera.captureSession)
                .ignoresSafeArea()

            // === VISUALIZER OVERLAY ===
            VisualizerOverlay(coordinator: coordinator)
                .ignoresSafeArea()

            // === TOP BAR ===
            VStack {
                topBar.padding(.top, 8)
                Spacer()
            }

            // === INSTRUMENT TOGGLES (right side, vertically centered) ===
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Spacer()
                    instToggle("PAD", icon: "◈", channel: "pad", color: Color(hex: "6366f1"))
                    instToggle("ARP", icon: "♪", channel: "arp", color: Color(hex: "22d3ee"))
                    instToggle("ARP2", icon: "♫", channel: "arp2", color: Color(hex: "2dd4bf"))
                    instToggle("MEL", icon: "🎵", channel: "melody", color: Color(hex: "a78bfa"))
                    instToggle("BEAT", icon: "◉", channel: "beat", color: Color(hex: "f87171"))
                    instToggle("BIN", icon: "∿", channel: "binaural", color: Color(hex: "818cf8"))
                    Spacer()
                }
                .padding(.trailing, 8)
            }

            // === VOLUME SLIDER (vertical, next to toggle) ===
            if let ch = volumeChannel {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("\(Int(volumeSliderValue)) dB")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        // Vertical slider
                        GeometryReader { geo in
                            let range: ClosedRange<Float> = -60...6
                            let pct = CGFloat((volumeSliderValue - range.lowerBound) / (range.upperBound - range.lowerBound))
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(0.15))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(accentColor.opacity(0.6))
                                    .frame(height: geo.size.height * pct)
                            }
                            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                                let pct = 1 - Float(v.location.y / geo.size.height)
                                volumeSliderValue = range.lowerBound + max(0, min(1, pct)) * (range.upperBound - range.lowerBound)
                                coordinator.audioEngine.setChannelVolume(ch, db: volumeSliderValue)
                            }.onEnded { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    volumeChannel = nil
                                }
                            })
                        }
                        .frame(width: 36, height: 150)
                    }
                    .padding(8)
                    .background(.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.trailing, 72)
                }
            }

            // === VERSION + CHORD BAR (bottom) ===
            VStack {
                Spacer()
                HStack {
                    Text("v3.3.1")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.8))
                    Spacer()
                    Circle()
                        .fill(coordinator.state.faceDetected ? .green : .red.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 12)
                chordBar
            }

            // === SYNTH PANEL (slides from right) ===
            if showSynthPanel {
                SynthPanelView(coordinator: coordinator, accentColor: accentColor, isPresented: $showSynthPanel)
                    .transition(.move(edge: .trailing))
            }

            // === MIXER PANEL (slides from bottom) ===
            if showMixer {
                MixerPanelView(coordinator: coordinator, isPresented: $showMixer)
                    .transition(.move(edge: .bottom))
            }

            // === TUTORIAL OVERLAY ===
            if showTutorial {
                TutorialView(isPresented: $showTutorial)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showSynthPanel)
        .animation(.easeInOut(duration: 0.25), value: showMixer)
        .animation(.easeInOut(duration: 0.2), value: showTutorial)
        .onAppear { coordinator.start() }
        .onDisappear { coordinator.stop() }
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Freeze button
            Button {
                coordinator.state.modeFrozen.toggle()
            } label: {
                Image(systemName: "snowflake")
                    .font(.system(size: 14))
                    .foregroundStyle(coordinator.state.modeFrozen ? .cyan : .white.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(coordinator.state.modeFrozen ? .cyan.opacity(0.2) : .white.opacity(0.08))
                    .clipShape(Circle())
            }

            // Mode name + valence
            VStack(spacing: 2) {
                Text(coordinator.state.currentModeName.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)

                GeometryReader { geo in
                    let pct = CGFloat((coordinator.state.lipCorner + 1) / 2)
                    let barW: CGFloat = geo.size.width * 0.12
                    let left = max(0, min(geo.size.width - barW, pct * geo.size.width - barW / 2))
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(.white.opacity(0.1)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 1.5).fill(accentColor).frame(width: barW, height: 3).offset(x: left)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: 140)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Riser
            Button {
                if coordinator.audioEngine.riserActive {
                    coordinator.audioEngine.dropRiser()
                } else {
                    coordinator.audioEngine.startRiser()
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(coordinator.audioEngine.riserActive ? .orange : .white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(coordinator.audioEngine.riserActive ? .orange.opacity(0.2) : .white.opacity(0.08))
                    .clipShape(Circle())
            }
            // Record
            Button {
                coordinator.recordingManager.toggleRecording()
            } label: {
                Image(systemName: coordinator.recordingManager.isRecording ? "stop.fill" : "circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(coordinator.recordingManager.isRecording ? .red : .red.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(coordinator.recordingManager.isRecording ? .red.opacity(0.2) : .white.opacity(0.08))
                    .clipShape(Circle())
            }
            // MIX
            Button { showMixer.toggle() } label: {
                Text("MIX")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            // Help
            Button { showTutorial.toggle() } label: {
                Text("?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
            // Settings
            Button { showSynthPanel.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 10)
    }

    private func topBarButton(icon: String, action: @escaping () -> Void, tint: Color = .white.opacity(0.7)) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08))
                .clipShape(Circle())
        }
    }

    // MARK: - Instrument Toggles

    private func instToggle(_ label: String, icon: String, channel: String, color: Color) -> some View {
        let active = !coordinator.audioEngine.isMuted(channel)
        return Button {
            coordinator.toggleMute(channel)
        } label: {
            VStack(spacing: 3) {
                Text(icon).font(.system(size: 18))
                Text(label).font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .frame(width: 56, height: 56)
            .background(active ? color.opacity(0.25) : .white.opacity(0.06))
            .foregroundStyle(active ? color : .white.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? color.opacity(0.5) : .white.opacity(0.08), lineWidth: 1))
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                volumeSliderValue = coordinator.audioEngine.channelVolumes[channel] ?? -10
                volumeChannel = channel
            }
        )
    }

    // MARK: - Chord Bar

    private var chordBar: some View {
        HStack(spacing: 0) {
            chordButton("I", index: 0)
            chordButton("ii", index: 1)
            chordButton("iii", index: 2)
            chordButton("IV", index: 3)
            chordButton("V", index: 4)
            chordButton("vi", index: 5)
        }
        .frame(height: 40)
        .background(.black.opacity(0.7))
    }

    private func chordButton(_ label: String, index: Int) -> some View {
        let active = coordinator.state.chordIndex == index
        return Button {
            coordinator.state.chordIndex = index
        } label: {
            Text(label)
                .font(.system(size: active ? 16 : 14, weight: active ? .bold : .regular, design: .monospaced))
                .foregroundStyle(active ? accentColor : .white.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(active ? accentColor.opacity(0.1) : .clear)
                .overlay(Rectangle().fill(active ? accentColor : .clear).frame(height: 2), alignment: .bottom)
        }
    }

    // MARK: - Accent Color

    var accentColor: Color {
        switch coordinator.state.currentModeName {
        case "lydian": return Color(hex: "fb923c")
        case "ionian": return Color(hex: "fbbf24")
        case "mixolydian": return Color(hex: "34d399")
        case "dorian": return Color(hex: "22d3ee")
        case "aeolian": return Color(hex: "818cf8")
        case "phrygian": return Color(hex: "a78bfa")
        default: return Color(hex: "e8a948")
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255
        g = Double((int >> 8) & 0xFF) / 255
        b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
