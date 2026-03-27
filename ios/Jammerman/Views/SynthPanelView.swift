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
            labelRow("preset", value: jammermanPresets[coordinator.state.presetIdx].name) {
                coordinator.state.presetIdx = (coordinator.state.presetIdx + 1) % jammermanPresets.count
                coordinator.audioEngine.applyPreset(jammermanPresets[coordinator.state.presetIdx], state: coordinator.state)
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

            // Tap Tempo
            HStack {
                Text("tap tempo").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button {
                    coordinator.audioEngine.tapTempo()
                } label: {
                    Text("TAP")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(accentColor.opacity(0.4), lineWidth: 1))
                }
            }

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
            HStack {
                Text("auto").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button {
                    coordinator.audioEngine.toggleChordAutoAdvance(state: coordinator.state)
                } label: {
                    Text(coordinator.audioEngine.chordAutoAdvance ? "AUTO" : "OFF")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(coordinator.audioEngine.chordAutoAdvance ? accentColor : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(coordinator.audioEngine.chordAutoAdvance ? accentColor.opacity(0.15) : .white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(coordinator.audioEngine.chordAutoAdvance ? accentColor.opacity(0.4) : .white.opacity(0.12), lineWidth: 1))
                }
            }

            sectionHeader("SCENES")
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { i in
                    let idx = i - 1
                    let hasScene = coordinator.sceneManager.hasScene(idx)
                    let isActive = coordinator.sceneManager.activeSlot == idx
                    let isSaveMode = coordinator.sceneManager.saveMode
                    Button {
                        coordinator.sceneManager.slotTapped(idx, coordinator: coordinator)
                    } label: {
                        Text("\(i)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(isActive ? accentColor : hasScene ? .white.opacity(0.8) : .white.opacity(0.4))
                            .frame(width: 40, height: 36)
                            .background(isSaveMode ? .orange.opacity(0.15) : isActive ? accentColor.opacity(0.15) : hasScene ? .white.opacity(0.1) : .white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                isSaveMode ? .orange.opacity(0.5) : isActive ? accentColor.opacity(0.5) : .white.opacity(0.12), lineWidth: 1))
                    }
                }
                Button {
                    coordinator.sceneManager.toggleSaveMode()
                } label: {
                    Text("SAVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(coordinator.sceneManager.saveMode ? .orange : .white.opacity(0.6))
                        .frame(width: 50, height: 36)
                        .background(coordinator.sceneManager.saveMode ? .orange.opacity(0.2) : .white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                            coordinator.sceneManager.saveMode ? .orange.opacity(0.5) : .white.opacity(0.12), lineWidth: 1))
                }
            }

            sectionHeader("LOOP RECORDER")
            // Progress bar
            if coordinator.loopRecorder.state != .empty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.1))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(loopProgressColor)
                            .frame(width: geo.size.width * coordinator.loopRecorder.progress, height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.bottom, 4)
            }

            HStack(spacing: 6) {
                // REC / STOP / OVR button
                Button {
                    coordinator.loopRecorder.onRecButton()
                } label: {
                    Text(coordinator.loopRecorder.recButtonLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: coordinator.loopRecorder.recButtonColor).opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                }

                // OVR button
                Button {
                    coordinator.loopRecorder.onOverdubButton()
                } label: {
                    Text("+ OVR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(coordinator.loopRecorder.canOverdub ? 0.7 : 0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                }
                .disabled(!coordinator.loopRecorder.canOverdub)

                // UNDO button
                Button {
                    coordinator.loopRecorder.undoLayer()
                } label: {
                    Text("UNDO")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(coordinator.loopRecorder.canUndo ? 0.7 : 0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                }
                .disabled(!coordinator.loopRecorder.canUndo)

                // Clear button
                Button {
                    coordinator.loopRecorder.clearAll()
                } label: {
                    Text("x")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(coordinator.loopRecorder.canClear ? 0.7 : 0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                }
                .disabled(!coordinator.loopRecorder.canClear)
            }

            // Bar count and layer count
            HStack(spacing: 12) {
                Button {
                    coordinator.loopRecorder.cycleBarCount()
                } label: {
                    Text("\(coordinator.loopRecorder.barCount) BAR\(coordinator.loopRecorder.barCount > 1 ? "S" : "")")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if coordinator.loopRecorder.layerCount > 0 {
                    Text("\(coordinator.loopRecorder.layerCount) layer\(coordinator.loopRecorder.layerCount > 1 ? "s" : "")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.top, 4)

            sectionHeader("GYROSCOPE")
            HStack {
                Text("tilt control").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button {
                    coordinator.gyroscopeManager.toggle()
                } label: {
                    Text(coordinator.gyroscopeManager.active ? "ON" : "OFF")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(coordinator.gyroscopeManager.active ? .green : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(coordinator.gyroscopeManager.active ? .green.opacity(0.15) : .white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(coordinator.gyroscopeManager.active ? .green.opacity(0.4) : .white.opacity(0.12), lineWidth: 1))
                }
            }
            if coordinator.gyroscopeManager.active {
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text("PAN").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
                        Text(String(format: "%.1f", coordinator.gyroscopeManager.panValue))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    }
                    VStack(spacing: 2) {
                        Text("REVERB").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
                        Text(String(format: "%.0f%%", coordinator.gyroscopeManager.reverbMod * 100))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var loopProgressColor: Color {
        switch coordinator.loopRecorder.state {
        case .recording: return .red
        case .overdubbing: return .orange
        default: return accentColor
        }
    }

    // MARK: - ARP Tab

    private func arpContent(id: Int) -> some View {
        let patterns = JammermanConfig.arpPatterns
        let noteValues = JammermanConfig.arpNoteValues
        let currentPattern = id == 1 ? coordinator.audioEngine.arpPattern : coordinator.audioEngine.arp2Pattern
        let currentNote = id == 1 ? coordinator.audioEngine.arpNoteValue : coordinator.audioEngine.arp2NoteValue

        let osc = id == 1 ? coordinator.audioEngine.arpOsc : coordinator.audioEngine.arp2Osc

        return VStack(spacing: 4) {
            sectionHeader("SYNTH")
            labelRow("wave", value: osc.waveformType.rawValue) {
                osc.waveformType = osc.waveformType.next
            }
            sliderRow("attack", value: Binding(get: { osc.attack }, set: { osc.attack = $0 }), range: 0.001...2)
            sliderRow("decay", value: Binding(get: { osc.decay }, set: { osc.decay = $0 }), range: 0.01...2)
            sliderRow("sustain", value: Binding(get: { osc.sustain }, set: { osc.sustain = $0 }), range: 0...1)
            sliderRow("release", value: Binding(get: { osc.releaseTime }, set: { osc.releaseTime = $0 }), range: 0.01...4)

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
        let mel = coordinator.audioEngine.melodyOsc
        return VStack(spacing: 4) {
            sectionHeader("MODE")
            labelRow("porta", value: mel.portamentoEnabled ? "ON" : "OFF") {
                mel.portamentoEnabled.toggle()
            }
            sliderRow("vibrato", value: Binding(get: { mel.vibratoAmount }, set: { mel.vibratoAmount = $0 }), range: 0...1)

            sectionHeader("SYNTH")
            labelRow("wave", value: mel.waveformType.rawValue) {
                mel.waveformType = mel.waveformType.next
            }
            sliderRow("attack", value: Binding(get: { mel.attack }, set: { mel.attack = $0 }), range: 0.001...2)
            sliderRow("decay", value: Binding(get: { mel.decay }, set: { mel.decay = $0 }), range: 0.01...2)
            sliderRow("sustain", value: Binding(get: { mel.sustain }, set: { mel.sustain = $0 }), range: 0...1)
            sliderRow("release", value: Binding(get: { mel.releaseTime }, set: { mel.releaseTime = $0 }), range: 0.01...4)
        }
    }

    // MARK: - PAD Tab

    private var padContent: some View {
        let pad = coordinator.audioEngine.padOsc
        return VStack(spacing: 4) {
            sectionHeader("SYNTH")
            labelRow("wave", value: pad.waveformType.rawValue) {
                pad.waveformType = pad.waveformType.next
            }
            sliderRow("harm", value: Binding(
                get: { Float(pad.harmonicity) }, set: { pad.harmonicity = Double($0) }
            ), range: 0.5...8, format: "%.1f")
            sliderRow("mod idx", value: Binding(
                get: { Float(pad.modulationIndex) }, set: { pad.modulationIndex = Double($0) }
            ), range: 0...10, format: "%.1f")
            sliderRow("attack", value: Binding(
                get: { Float(pad.attackRate * 44100) }, set: { pad.attackRate = 1.0 / (Double($0) * 44100) }
            ), range: 0.01...4)
            sliderRow("release", value: Binding(
                get: { Float(pad.releaseRate * 44100 * 3) }, set: { pad.releaseRate = 1.0 / (Double($0) * 44100) }
            ), range: 0.1...8)
        }
    }

    // MARK: - DRUMS Tab

    private var drumsContent: some View {
        VStack(spacing: 4) {
            sectionHeader("STEP SEQUENCER")
            labelRow("source", value: "custom") { /* reserved */ }
            labelRow("preset", value: "Custom") { /* reserved */ }

            // Step grid with current step highlight
            if coordinator.audioEngine.drumPattern.count >= 3 {
                let drumLabels = ["HH", "SN", "KK"]
                let steps = coordinator.audioEngine.drumPattern[0].count
                let currentStep = coordinator.audioEngine.drumStep % steps

                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { drum in
                        HStack(spacing: 2) {
                            Text(drumLabels[drum])
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: 20)
                            ForEach(0..<steps, id: \.self) { step in
                                let active = coordinator.audioEngine.drumPattern[drum][step] == 1
                                let isCurrentStep = step == currentStep
                                Rectangle()
                                    .fill(active ? drumColor(drum) : isCurrentStep ? .white.opacity(0.15) : .white.opacity(0.06))
                                    .frame(height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(isCurrentStep ? .white.opacity(0.5) : .white.opacity(0.08), lineWidth: isCurrentStep ? 1.5 : 0.5)
                                    )
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

// Presets are defined in Presets.swift (jammermanPresets array)
