// Jammerman — Synth Panel (Settings)
// Slides from right, 7 tabs: PERFORM, ARP1, ARP2, MELODY, PAD, DRUMS, BIN
// Matches web app layout exactly

import SwiftUI

struct SynthPanelView: View {
    @ObservedObject var coordinator: TrackingCoordinator
    let accentColor: Color
    @Binding var isPresented: Bool
    @State private var selectedTab = "perform"

    var body: some View {
        HStack(spacing: 0) {
            // Tap-to-dismiss left area
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }
                .frame(maxWidth: .infinity)

            // Panel
            VStack(spacing: 0) {
                // Close chevron
                HStack {
                    Button { isPresented = false } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(8)
                    }
                    Spacer()
                }

                // Tab bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        panelTab("PERFORM", id: "perform")
                        panelTab("ARP\n1", id: "arp1")
                        panelTab("ARP\n2", id: "arp2")
                        panelTab("MELODY", id: "melody")
                        panelTab("PAD", id: "pad")
                        panelTab("DRUMS", id: "drums")
                        panelTab("BIN", id: "bin")
                    }
                }
                .padding(.horizontal, 8)

                Divider().background(.white.opacity(0.1))

                // Content
                ScrollView(showsIndicators: false) {
                    Group {
                        switch selectedTab {
                        case "perform": performContent
                        case "arp1": arpContent(id: 1)
                        case "arp2": arpContent(id: 2)
                        case "melody": melodyContent
                        case "pad": padContent
                        case "drums": drumsContent
                        case "bin": binContent
                        default: performContent
                        }
                    }
                    .padding(12)
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.62)
            .background(.black.opacity(0.92))
        }
        .ignoresSafeArea()
    }

    // MARK: - Tab Button

    private func panelTab(_ title: String, id: String) -> some View {
        Button { selectedTab = id } label: {
            Text(title)
                .font(.system(size: 10, weight: selectedTab == id ? .heavy : .medium, design: .monospaced))
                .foregroundStyle(selectedTab == id ? accentColor : .white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(selectedTab == id ? accentColor.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor.opacity(0.6))
                .tracking(2)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Row Helpers

    private func labelRow(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Button(action: action) {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.12), lineWidth: 1))
            }
        }
    }

    private func sliderRow(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, format: String = "%.2f") -> some View {
        HStack {
            Text(label).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.5)).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range).tint(accentColor)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - PERFORM Tab

    private var performContent: some View {
        VStack(spacing: 4) {
            sectionHeader("PRESET")
            labelRow("preset", value: JammermanConfig.presetNames[coordinator.state.presetIdx]) {
                coordinator.state.presetIdx = (coordinator.state.presetIdx + 1) % JammermanConfig.presetNames.count
            }

            sectionHeader("TEMPO")
            sliderRow("BPM", value: Binding(
                get: { Float(coordinator.audioEngine.bpm) },
                set: { coordinator.audioEngine.setBPM(Double($0)) }
            ), range: 40...200, format: "%.0f")
            sliderRow("swing", value: Binding(
                get: { Float(coordinator.audioEngine.swing) },
                set: { coordinator.audioEngine.swing = Int($0) }
            ), range: 0...80, format: "%.0f%%")

            sectionHeader("KEY & SCALE")
            labelRow("key", value: JammermanConfig.noteNames[coordinator.state.rootOffset]) {
                coordinator.state.rootOffset = (coordinator.state.rootOffset + 1) % 12
            }
            labelRow("scale", value: coordinator.state.extraScaleMode ?? "Modal (face)") {
                let scales = ["Modal (face)"] + Array(Scale.extra.keys.sorted())
                let current = coordinator.state.extraScaleMode ?? "Modal (face)"
                let idx = scales.firstIndex(of: current) ?? 0
                let next = scales[(idx + 1) % scales.count]
                coordinator.state.extraScaleMode = next == "Modal (face)" ? nil : next
            }

            sectionHeader("CHORDS")
            labelRow("auto", value: "OFF") { /* TODO: chord auto-advance */ }

            sectionHeader("SCENES")
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { i in
                    Button { /* TODO: recall scene */ } label: {
                        Text("\(i)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 40, height: 36)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1))
                    }
                }
                Button { /* TODO: save scene */ } label: {
                    Text("SAVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 50, height: 36)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1))
                }
            }

            sectionHeader("LOOP RECORDER")
            HStack(spacing: 6) {
                loopButton("● REC", color: .red)
                loopButton("+ OVR", color: .white)
                loopButton("UNDO", color: .white)
                loopButton("×", color: .white)
            }
        }
    }

    private func loopButton(_ label: String, color: Color) -> some View {
        Button { /* TODO */ } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
        }
    }

    // MARK: - ARP Tab

    private func arpContent(id: Int) -> some View {
        let patterns = JammermanConfig.arpPatterns
        let noteValues = JammermanConfig.arpNoteValues
        let currentPattern = id == 1 ? coordinator.audioEngine.arpPattern : coordinator.audioEngine.arp2Pattern
        let currentNote = id == 1 ? coordinator.audioEngine.arpNoteValue : coordinator.audioEngine.arp2NoteValue

        return VStack(spacing: 4) {
            sectionHeader("SYNTH")
            labelRow("wave", value: "sawtooth") { /* TODO: waveform cycle */ }
            sliderRow("attack", value: .constant(Float(0.01)), range: 0.001...2)
            sliderRow("decay", value: .constant(Float(0.30)), range: 0.01...2)
            sliderRow("sustain", value: .constant(Float(0.60)), range: 0...1)
            sliderRow("release", value: .constant(Float(0.80)), range: 0.01...4)

            sectionHeader("PATTERN")
            labelRow("pattern", value: currentPattern) {
                let idx = patterns.firstIndex(of: currentPattern) ?? 0
                let next = patterns[(idx + 1) % patterns.count]
                if id == 1 { coordinator.audioEngine.setArpPattern(next) }
                else { coordinator.audioEngine.setArp2Pattern(next) }
            }
            labelRow("note", value: currentNote) {
                let idx = noteValues.firstIndex(of: currentNote) ?? 0
                let next = noteValues[(idx + 1) % noteValues.count]
                if id == 1 { coordinator.audioEngine.setArpNoteValue(next) }
                else { coordinator.audioEngine.setArp2NoteValue(next) }
            }
        }
    }

    // MARK: - MELODY Tab

    private var melodyContent: some View {
        VStack(spacing: 4) {
            sectionHeader("MODE")
            labelRow("porta", value: coordinator.audioEngine.melodyOsc.portamentoEnabled ? "ON" : "OFF") {
                coordinator.audioEngine.melodyOsc.portamentoEnabled.toggle()
            }
            sliderRow("vibrato", value: .constant(Float(0.0)), range: 0...1)

            sectionHeader("SYNTH")
            labelRow("wave", value: "triangle") { /* TODO */ }
            sliderRow("attack", value: .constant(Float(0.05)), range: 0.001...2)
            sliderRow("decay", value: .constant(Float(0.20)), range: 0.01...2)
            sliderRow("sustain", value: .constant(Float(0.70)), range: 0...1)
            sliderRow("release", value: .constant(Float(0.40)), range: 0.01...4)
        }
    }

    // MARK: - PAD Tab

    private var padContent: some View {
        VStack(spacing: 4) {
            sectionHeader("SYNTH")
            labelRow("wave", value: "sine") { /* TODO */ }
            sliderRow("harm", value: Binding(
                get: { Float(coordinator.audioEngine.padOsc.harmonicity) },
                set: { coordinator.audioEngine.padOsc.harmonicity = Double($0) }
            ), range: 0.5...8, format: "%.1f")
            sliderRow("mod idx", value: Binding(
                get: { Float(coordinator.audioEngine.padOsc.modulationIndex) },
                set: { coordinator.audioEngine.padOsc.modulationIndex = Double($0) }
            ), range: 0...10, format: "%.1f")
            sliderRow("attack", value: .constant(Float(1.0)), range: 0.01...4)
            sliderRow("release", value: .constant(Float(2.5)), range: 0.1...8)
        }
    }

    // MARK: - DRUMS Tab

    private var drumsContent: some View {
        VStack(spacing: 4) {
            sectionHeader("STEP SEQUENCER")
            labelRow("source", value: "custom") { /* TODO */ }
            labelRow("preset", value: "Custom") { /* TODO: cycle presets */ }

            // Step grid
            if coordinator.audioEngine.drumPattern.count >= 3 {
                let drumLabels = ["HH", "SN", "KK"]
                let steps = coordinator.audioEngine.drumPattern[0].count

                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { drum in
                        HStack(spacing: 2) {
                            Text(drumLabels[drum])
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 20)
                            ForEach(0..<steps, id: \.self) { step in
                                let active = coordinator.audioEngine.drumPattern[drum][step] == 1
                                Rectangle()
                                    .fill(active ? drumColor(drum) : .white.opacity(0.06))
                                    .frame(height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.08), lineWidth: 0.5))
                                    .onTapGesture {
                                        coordinator.audioEngine.setDrumStep(drum: drum, step: step, active: !active)
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)

                HStack(spacing: 12) {
                    Button { clearDrums() } label: {
                        Text("clear")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                    }
                    Button { /* TODO */ } label: {
                        Text("copy preset")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                    }
                }
            }
        }
    }

    private func drumColor(_ drum: Int) -> Color {
        switch drum {
        case 0: return Color(hex: "00dcff") // HH cyan
        case 1: return Color(hex: "fff0b4") // SN yellow
        case 2: return Color(hex: "ff5a28") // KK red-orange
        default: return .white
        }
    }

    private func clearDrums() {
        let empty = Array(repeating: 0, count: 16)
        coordinator.audioEngine.setDrumPattern([empty, empty, empty])
    }

    // MARK: - BINAURAL Tab

    private var binContent: some View {
        VStack(spacing: 4) {
            sectionHeader("BINAURAL BEATS")
            labelRow("on/off", value: coordinator.audioEngine.binauralActive ? "ON" : "OFF") {
                coordinator.audioEngine.toggleBinaural()
            }
            labelRow("mode", value: coordinator.audioEngine.binauralFollowChord ? "chord" : "tonic") {
                coordinator.audioEngine.binauralFollowChord.toggle()
            }
            sliderRow("beat hz", value: Binding(
                get: { coordinator.audioEngine.binauralBeatHz },
                set: { coordinator.audioEngine.setBinauralBeatHz($0) }
            ), range: 0.5...20, format: "%.1f")
        }
    }
}

// MARK: - Preset Names

extension JammermanConfig {
    static let presetNames = ["Default", "Ambient Dream", "Dark Techno", "Lo-Fi Chill", "Bright Pop", "Deep Space", "Minimal", "Future Bass"]
}
