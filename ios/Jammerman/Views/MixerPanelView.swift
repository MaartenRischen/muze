// Jammerman — Mixer Panel
// Horizontal scrolling channel strips with faders, M/S buttons
// Tap channel header for detail view (EQ, sends, pan)
// All controls fully wired to AudioEngine parameters

import SwiftUI

struct MixerPanelView: View {
    @ObservedObject var coordinator: TrackingCoordinator
    @Binding var isPresented: Bool
    @State private var detailChannel: String? = nil

    private let channels = [
        ("PAD", "pad", Color(hex: "6366f1")),
        ("ARP", "arp", Color(hex: "22d3ee")),
        ("ARP2", "arp2", Color(hex: "2dd4bf")),
        ("MELO", "melody", Color(hex: "a78bfa")),
        ("KICK", "kick", Color(hex: "f87171")),
        ("SNARE", "snare", Color(hex: "fb923c")),
        ("HAT", "hat", Color(hex: "fbbf24")),
        ("MSTR", "master", Color(hex: "a3a3a3")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("M I X E R")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if let ch = detailChannel {
                    channelDetail(ch)
                } else {
                    // Channel strip overview
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(channels, id: \.1) { name, id, color in
                                channelStrip(name: name, id: id, color: color)
                            }
                        }
                    }
                    .frame(height: 300)
                }
            }
            .background(.black.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .ignoresSafeArea()
    }

    // MARK: - Channel Strip

    private func channelStrip(name: String, id: String, color: Color) -> some View {
        ChannelStripView(name: name, id: id, color: color, coordinator: coordinator, detailChannel: $detailChannel)
    }

    // MARK: - Channel Detail (stays in MixerPanelView for access to channels/detailChannel)
}

// Separate view for channel strip so @State works for fader drag
struct ChannelStripView: View {
    let name: String
    let id: String
    let color: Color
    @ObservedObject var coordinator: TrackingCoordinator
    @Binding var detailChannel: String?
    @State private var dragVolume: Float? = nil // local tracking during drag

    var body: some View {
        let vol = dragVolume ?? (coordinator.audioEngine.channelVolumes[id] ?? -10)
        let muted = id == "master" ? false : coordinator.audioEngine.isMuted(id)
        let soloed = coordinator.audioEngine.soloChannel == id
        let stripWidth: CGFloat = (UIScreen.main.bounds.width - 20) / 7.5
        let pct = CGFloat((vol + 60) / 66)

        VStack(spacing: 0) {
            // Header — tap to open detail
            Button { detailChannel = id } label: {
                Text(name)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(color)
            }

            // Fader
            GeometryReader { geo in
                ZStack {
                    Rectangle().fill(.white.opacity(0.05))

                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(color.opacity(muted ? 0.1 : 0.3))
                            .frame(height: geo.size.height * max(0, min(1, pct)))
                    }

                    let y = geo.size.height * (1 - max(0, min(1, pct)))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.7))
                        .frame(width: stripWidth * 0.6, height: 8)
                        .position(x: geo.size.width / 2, y: y)
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let pctNew = 1 - Float(v.location.y / geo.size.height)
                        let db = -60 + max(0, min(1, pctNew)) * 66
                        dragVolume = db
                        if id != "master" {
                            coordinator.audioEngine.setChannelVolume(id, db: db)
                        }
                    }
                    .onEnded { _ in
                        dragVolume = nil
                    }
                )
            }
            .frame(height: 200)

            Text("\(Int(vol))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.vertical, 2)

            // Pan dot
            let pan = coordinator.audioEngine.channelPans[id] ?? 0
            HStack(spacing: 1) {
                Rectangle().fill(pan < -0.05 ? color.opacity(0.5) : .white.opacity(0.1))
                    .frame(width: stripWidth * 0.2, height: 4)
                Rectangle().fill(abs(pan) < 0.1 ? color.opacity(0.3) : .white.opacity(0.1))
                    .frame(width: stripWidth * 0.1, height: 4)
                Rectangle().fill(pan > 0.05 ? color.opacity(0.5) : .white.opacity(0.1))
                    .frame(width: stripWidth * 0.2, height: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))

            // M / S
            HStack(spacing: 2) {
                Button {
                    if id != "master" { coordinator.toggleMute(id) }
                } label: {
                    Text("M")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(muted ? .red : .white.opacity(0.4))
                        .frame(width: stripWidth * 0.4, height: 22)
                        .background(muted ? .red.opacity(0.15) : .white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Button {
                    if id != "master" { coordinator.audioEngine.toggleSolo(id) }
                } label: {
                    Text("S")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(soloed ? .yellow : .white.opacity(0.4))
                        .frame(width: stripWidth * 0.4, height: 22)
                        .background(soloed ? .yellow.opacity(0.15) : .white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.bottom, 8)
        }
        .frame(width: stripWidth)
    }
}

// MARK: - Channel Detail (extension on MixerPanelView)

extension MixerPanelView {
    func channelDetail(_ id: String) -> some View {
        ChannelDetailView(id: id, channels: channels, coordinator: coordinator, detailChannel: $detailChannel)
    }
}

// Separate view so @State bindings work for responsive sliders
struct ChannelDetailView: View {
    let id: String
    let channels: [(String, String, Color)]
    @ObservedObject var coordinator: TrackingCoordinator
    @Binding var detailChannel: String?

    // Local state for responsive sliders
    @State private var localPan: Float? = nil
    @State private var localReverbSend: Float? = nil
    @State private var localDelaySend: Float? = nil
    @State private var localEqLow: Float? = nil
    @State private var localEqMid: Float? = nil
    @State private var localEqHigh: Float? = nil

    var body: some View {
        let name = channels.first(where: { $0.1 == id })?.0 ?? id
        let color = channels.first(where: { $0.1 == id })?.2 ?? .white

        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text(name)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Button { detailChannel = nil } label: {
                        Text("BACK")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                    }
                }

                // EQ
                sectionHeader("EQUALIZER")
                eqRow("LOW", band: 0, local: $localEqLow, color: color)
                eqRow("MID", band: 1, local: $localEqMid, color: color)
                eqRow("HIGH", band: 2, local: $localEqHigh, color: color)

                if id != "master" {
                    // Sends
                    sectionHeader("SENDS")
                    sendRow("REVERB", local: $localReverbSend, isReverb: true, color: color)
                    sendRow("DELAY", local: $localDelaySend, isReverb: false, color: color)

                    // Pan
                    sectionHeader("PAN")
                    panRow(color: color)
                }
            }
            .padding(16)
        }
        .frame(height: 400)
        .onAppear {
            // Load current values into local state
            let eqGains = coordinator.audioEngine.channelEQGains[id] ?? [0, 0, 0]
            localEqLow = eqGains[0]
            localEqMid = eqGains[1]
            localEqHigh = eqGains[2]
            localPan = coordinator.audioEngine.channelPans[id] ?? 0
            localReverbSend = coordinator.audioEngine.channelReverbSends[id] ?? 0
            localDelaySend = coordinator.audioEngine.channelDelaySends[id] ?? 0
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(2)
            Spacer()
        }
    }

    private func eqRow(_ label: String, band: Int, local: Binding<Float?>, color: Color) -> some View {
        let value = local.wrappedValue ?? 0
        return HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 40, alignment: .leading)
            Slider(value: Binding(
                get: { value },
                set: { new in
                    local.wrappedValue = new
                    coordinator.audioEngine.setChannelEQ(id, band: band, gain: new)
                }
            ), in: -12...12)
            .tint(color)
            Text("\(Int(value)) dB")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 45, alignment: .trailing)
        }
    }

    private func sendRow(_ label: String, local: Binding<Float?>, isReverb: Bool, color: Color) -> some View {
        let value = local.wrappedValue ?? 0
        return HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 55, alignment: .leading)
            Slider(value: Binding(
                get: { value },
                set: { new in
                    local.wrappedValue = new
                    if isReverb {
                        coordinator.audioEngine.setChannelReverbSend(id, amount: new)
                    } else {
                        coordinator.audioEngine.setChannelDelaySend(id, amount: new)
                    }
                }
            ), in: 0...1)
            .tint(color)
            Text("\(Int(value * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 35, alignment: .trailing)
        }
    }

    private func panRow(color: Color) -> some View {
        let value = localPan ?? 0
        return HStack {
            Text("L")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            Slider(value: Binding(
                get: { (value + 1) / 2 }, // -1..1 → 0..1
                set: { new in
                    let pan = new * 2 - 1 // 0..1 → -1..1
                    localPan = pan
                    coordinator.audioEngine.setChannelPan(id, pan: pan)
                }
            ), in: 0...1)
            .tint(color)
            Text("R")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            Text(panLabel(value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 35, alignment: .trailing)
        }
    }

    private func panLabel(_ pan: Float) -> String {
        if abs(pan) < 0.05 { return "C" }
        if pan < 0 { return "L\(Int(abs(pan) * 100))" }
        return "R\(Int(pan * 100))"
    }
}
