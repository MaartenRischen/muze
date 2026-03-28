// Jammerman — Instrument Detail View
// Full settings panel for each instrument, opened by long-pressing its toggle button
// Shows: mixer (vol/pan/sends/EQ), synth params, pattern settings, preset picker

import SwiftUI

struct InstrumentDetailView: View {
    let channel: String
    let color: Color
    @ObservedObject var coordinator: TrackingCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.95).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Text(channelDisplayName.uppercased())
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundStyle(color)
                        Spacer()
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 8)

                    // Preset picker (if applicable)
                    if hasPresets {
                        presetSection
                    }

                    // Mixer section
                    mixerSection

                    // Synth/instrument-specific section
                    if hasSynthParams {
                        synthSection
                    }

                    // Pattern section (arp/drums)
                    if hasPatternSettings {
                        patternSection
                    }

                    // Binaural-specific
                    if channel == "binaural" {
                        binauralSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private var engine: AudioEngine { coordinator.audioEngine }

    private var channelDisplayName: String {
        switch channel {
        case "pad": return "Pad"
        case "arp": return "Arp 1"
        case "arp2": return "Arp 2"
        case "melody": return "Melody"
        case "beat": return "Drums"
        case "binaural": return "Binaural"
        default: return channel
        }
    }

    private var hasPresets: Bool {
        ["pad", "arp", "arp2", "melody", "beat"].contains(channel)
    }

    private var hasSynthParams: Bool {
        ["pad", "arp", "arp2", "melody"].contains(channel)
    }

    private var hasPatternSettings: Bool {
        ["arp", "arp2", "beat"].contains(channel)
    }

    // MARK: - Preset Section

    @ViewBuilder
    private var presetSection: some View {
        sectionHeader("PRESET")
        if engine.useSoundFont {
            let presets = presetsForChannel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<presets.count, id: \.self) { idx in
                        Button {
                            selectPreset(idx)
                        } label: {
                            Text(presets[idx])
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(color.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        } else {
            Text("Using built-in synth")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var presetsForChannel: [String] {
        switch channel {
        case "pad": return SoundFontManager.padPresets.map(\.name)
        case "melody": return SoundFontManager.leadPresets.map(\.name)
        case "arp": return SoundFontManager.arpPresets.map(\.name)
        case "arp2": return SoundFontManager.arpPresets.map(\.name)
        case "beat": return SoundFontManager.drumPresets.map(\.name)
        default: return []
        }
    }

    private func selectPreset(_ idx: Int) {
        guard let sfm = engine.soundFontManager else { return }
        switch channel {
        case "pad": sfm.loadPadPreset(idx)
        case "melody": sfm.loadLeadPreset(idx)
        case "arp": sfm.loadArpPreset(idx, sampler: sfm.arpSampler)
        case "arp2": sfm.loadArpPreset(idx, sampler: sfm.arp2Sampler)
        case "beat": sfm.loadDrumPreset(idx)
        default: break
        }
    }

    // MARK: - Mixer Section

    @ViewBuilder
    private var mixerSection: some View {
        sectionHeader("MIXER")

        let mixerChannels: [String] = channel == "beat" ? ["kick", "snare", "hat"] : [channel]

        ForEach(mixerChannels, id: \.self) { ch in
            if channel == "beat" {
                Text(ch.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color.opacity(0.7))
                    .padding(.top, 4)
            }
            MixerControls(channel: ch, color: color, engine: engine)
        }
    }

    // MARK: - Synth Section

    @ViewBuilder
    private var synthSection: some View {
        sectionHeader("SYNTH")

        if channel == "pad" {
            paramSlider("Harmonicity", value: engine.padOsc.harmonicity, range: 0.5...8, step: 0.1) {
                engine.padOsc.harmonicity = $0
            }
            paramSlider("Mod Index", value: engine.padOsc.modulationIndex, range: 0...10, step: 0.1) {
                engine.padOsc.modulationIndex = $0
            }
        }

        if channel == "arp" {
            arpADSR(osc: engine.arpOsc)
        }
        if channel == "arp2" {
            arpADSR(osc: engine.arp2Osc)
        }
        if channel == "melody" {
            paramSlider("Attack", value: Double(engine.melodyOsc.attack), range: 0.001...2, step: 0.01) {
                engine.melodyOsc.attack = Float($0)
            }
            paramSlider("Decay", value: Double(engine.melodyOsc.decay), range: 0.01...2, step: 0.01) {
                engine.melodyOsc.decay = Float($0)
            }
            paramSlider("Sustain", value: Double(engine.melodyOsc.sustain), range: 0...1, step: 0.01) {
                engine.melodyOsc.sustain = Float($0)
            }
            paramSlider("Release", value: Double(engine.melodyOsc.releaseTime), range: 0.01...4, step: 0.01) {
                engine.melodyOsc.releaseTime = Float($0)
            }
            paramSlider("Vibrato", value: Double(engine.melodyOsc.vibratoAmount), range: 0...1, step: 0.01) {
                engine.melodyOsc.vibratoAmount = Float($0)
            }
            Toggle("Portamento", isOn: Binding(
                get: { engine.melodyOsc.portamentoEnabled },
                set: { engine.melodyOsc.portamentoEnabled = $0 }
            ))
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
            .tint(color)
        }
    }

    // MARK: - Pattern Section

    @ViewBuilder
    private var patternSection: some View {
        sectionHeader("PATTERN")

        if channel == "arp" || channel == "arp2" {
            let isArp1 = channel == "arp"
            let currentPattern = isArp1 ? engine.arpPattern : engine.arp2Pattern
            let currentNoteValue = isArp1 ? engine.arpNoteValue : engine.arp2NoteValue

            Text("Direction")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 6) {
                ForEach(["up", "down", "up-down", "random"], id: \.self) { pat in
                    Button {
                        if isArp1 { engine.setArpPattern(pat) }
                        else { engine.setArp2Pattern(pat) }
                    } label: {
                        Text(pat)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(currentPattern == pat ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(currentPattern == pat ? color.opacity(0.4) : .white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }

            Text("Note Value")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 6)

            HStack(spacing: 6) {
                ForEach(["4n", "8n", "8n.", "16n", "16n.", "32n"], id: \.self) { nv in
                    Button {
                        if isArp1 { engine.setArpNoteValue(nv) }
                        else { engine.setArp2NoteValue(nv) }
                    } label: {
                        Text(nv)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(currentNoteValue == nv ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(currentNoteValue == nv ? color.opacity(0.4) : .white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }

        if channel == "beat" {
            DrumPatternGrid(engine: engine, color: color)
        }
    }

    // MARK: - Binaural Section

    @ViewBuilder
    private var binauralSection: some View {
        sectionHeader("BINAURAL")

        paramSlider("Beat Hz", value: Double(engine.binauralBeatHz), range: 0.5...20, step: 0.5) {
            engine.setBinauralBeatHz(Float($0))
        }

        Toggle("Follow Chord", isOn: Binding(
            get: { engine.binauralFollowChord },
            set: { engine.binauralFollowChord = $0 }
        ))
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.7))
        .tint(color)
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func arpADSR(osc: ArpOscillator) -> some View {
        paramSlider("Attack", value: Double(osc.attack), range: 0.001...2, step: 0.01) {
            osc.attack = Float($0)
        }
        paramSlider("Decay", value: Double(osc.decay), range: 0.01...2, step: 0.01) {
            osc.decay = Float($0)
        }
        paramSlider("Sustain", value: Double(osc.sustain), range: 0...1, step: 0.01) {
            osc.sustain = Float($0)
        }
        paramSlider("Release", value: Double(osc.releaseTime), range: 0.01...4, step: 0.01) {
            osc.releaseTime = Float($0)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .foregroundStyle(color.opacity(0.6))
            .padding(.top, 8)
    }

    private func paramSlider(_ label: String, value: Double, range: ClosedRange<Double>, step: Double, onChange: @escaping (Double) -> Void) -> some View {
        LiveParamSlider(label: label, initialValue: value, range: range, step: step, color: color, onChange: onChange)
    }
}

// MARK: - Mixer Controls (Volume, Pan, Sends, EQ)

private struct MixerControls: View {
    let channel: String
    let color: Color
    let engine: AudioEngine

    var body: some View {
        VStack(spacing: 8) {
            mixerSlider("Volume", value: Double(engine.channelVolumes[channel] ?? -10), range: -60...6, unit: "dB") {
                engine.setChannelVolume(channel, db: Float($0))
            }
            mixerSlider("Pan", value: Double(engine.channelPans[channel] ?? 0), range: -1...1, unit: "") {
                engine.setChannelPan(channel, pan: Float($0))
            }
            mixerSlider("Reverb", value: Double(engine.channelReverbSends[channel] ?? 0) * 100, range: 0...100, unit: "%") {
                engine.setChannelReverbSend(channel, amount: Float($0 / 100))
            }
            mixerSlider("Delay", value: Double(engine.channelDelaySends[channel] ?? 0) * 100, range: 0...100, unit: "%") {
                engine.setChannelDelaySend(channel, amount: Float($0 / 100))
            }

            // EQ
            let eqGains = engine.channelEQGains[channel] ?? [0, 0, 0]
            let bands = ["Low", "Mid", "High"]
            ForEach(0..<min(3, eqGains.count), id: \.self) { band in
                mixerSlider("EQ \(bands[band])", value: Double(eqGains[band]), range: -12...12, unit: "dB") {
                    engine.setChannelEQ(channel, band: band, gain: Float($0))
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func mixerSlider(_ label: String, value: Double, range: ClosedRange<Double>, unit: String, onChange: @escaping (Double) -> Void) -> some View {
        LiveMixerSlider(label: label, initialValue: value, range: range, unit: unit, color: color, onChange: onChange)
    }
}

// MARK: - Live Param Slider (@State-backed for responsive dragging)

private struct LiveParamSlider: View {
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let color: Color
    let onChange: (Double) -> Void

    @State private var current: Double

    init(label: String, initialValue: Double, range: ClosedRange<Double>, step: Double, color: Color, onChange: @escaping (Double) -> Void) {
        self.label = label
        self.range = range
        self.step = step
        self.color = color
        self.onChange = onChange
        _current = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.2f", current))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color.opacity(0.7))
            }
            Slider(value: $current, in: range, step: step)
                .tint(color)
                .onChange(of: current) { _, newVal in onChange(newVal) }
        }
    }
}

// MARK: - Live Mixer Slider (@State-backed)

private struct LiveMixerSlider: View {
    let label: String
    let range: ClosedRange<Double>
    let unit: String
    let color: Color
    let onChange: (Double) -> Void

    @State private var current: Double

    init(label: String, initialValue: Double, range: ClosedRange<Double>, unit: String, color: Color, onChange: @escaping (Double) -> Void) {
        self.label = label
        self.range = range
        self.unit = unit
        self.color = color
        self.onChange = onChange
        _current = State(initialValue: initialValue)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 52, alignment: .leading)
            Slider(value: $current, in: range)
                .tint(color)
                .onChange(of: current) { _, newVal in onChange(newVal) }
            Text("\(Int(current))\(unit)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.6))
                .frame(width: 42, alignment: .trailing)
        }
    }
}

// MARK: - Drum Pattern Grid

private struct DrumPatternGrid: View {
    let engine: AudioEngine
    let color: Color

    private let drumLabels = ["HH", "SN", "KK"]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<min(3, engine.drumPattern.count), id: \.self) { drum in
                HStack(spacing: 3) {
                    Text(drumLabels[drum])
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 22)

                    ForEach(0..<min(16, engine.drumPattern[drum].count), id: \.self) { step in
                        let active = engine.drumPattern[drum][step] == 1
                        let isCurrent = engine.drumStep == step
                        Button {
                            engine.setDrumStep(drum: drum, step: step, active: !active)
                        } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(active ? color.opacity(isCurrent ? 1 : 0.6) : .white.opacity(isCurrent ? 0.15 : 0.05))
                                .frame(height: 22)
                        }
                    }
                }
            }
        }
    }
}
