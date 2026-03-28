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

// DAW-style channel detail — organized like Logic Pro channel strip
struct ChannelDetailView: View {
    let id: String
    let channels: [(String, String, Color)]
    @ObservedObject var coordinator: TrackingCoordinator
    @Binding var detailChannel: String?

    // Local Double state for responsive Slider binding (SwiftUI Slider uses Double)
    @State private var pan: Double = 0
    @State private var reverbSend: Double = 0
    @State private var delaySend: Double = 0
    @State private var eqLow: Double = 0
    @State private var eqMid: Double = 0
    @State private var eqHigh: Double = 0

    var body: some View {
        let name = channels.first(where: { $0.1 == id })?.0 ?? id
        let color = channels.first(where: { $0.1 == id })?.2 ?? .white

        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text(name)
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
                Button { detailChannel = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Channel strip content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // === PAN (top, most used) ===
                    if id != "master" {
                        VStack(spacing: 6) {
                            HStack {
                                Text("PAN")
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(color.opacity(0.7))
                                Spacer()
                                Text(panLabel)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            HStack(spacing: 8) {
                                Text("L").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.25))
                                Slider(value: $pan, in: -1...1)
                                    .tint(color)
                                    .onChange(of: pan) { _, new in
                                        coordinator.audioEngine.setChannelPan(id, pan: Float(new))
                                    }
                                Text("R").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.25))
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // === SENDS ===
                    if id != "master" {
                        VStack(spacing: 12) {
                            HStack {
                                Text("SENDS")
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(color.opacity(0.7))
                                Spacer()
                            }
                            sliderRow("Reverb", value: $reverbSend, color: color) { new in
                                coordinator.audioEngine.setChannelReverbSend(id, amount: Float(new))
                            }
                            sliderRow("Delay", value: $delaySend, color: color) { new in
                                coordinator.audioEngine.setChannelDelaySend(id, amount: Float(new))
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // === EQ ===
                    VStack(spacing: 12) {
                        HStack {
                            Text("EQ")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundStyle(color.opacity(0.7))
                            Spacer()
                        }
                        eqSlider("Low", value: $eqLow, color: color, band: 0)
                        eqSlider("Mid", value: $eqMid, color: color, band: 1)
                        eqSlider("High", value: $eqHigh, color: color, band: 2)
                    }
                    .padding(12)
                    .background(.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Spacer().frame(height: 40) // safe area padding
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(height: 380)
        .onAppear { loadValues() }
    }

    private func loadValues() {
        let eqGains = coordinator.audioEngine.channelEQGains[id] ?? [0, 0, 0]
        eqLow = Double(eqGains[0])
        eqMid = Double(eqGains[1])
        eqHigh = Double(eqGains[2])
        pan = Double(coordinator.audioEngine.channelPans[id] ?? 0)
        reverbSend = Double(coordinator.audioEngine.channelReverbSends[id] ?? 0)
        delaySend = Double(coordinator.audioEngine.channelDelaySends[id] ?? 0)
    }

    private func sliderRow(_ label: String, value: Binding<Double>, color: Color, onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 50, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(color)
                .onChange(of: value.wrappedValue) { _, new in onChange(new) }
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 35, alignment: .trailing)
        }
    }

    private func eqSlider(_ label: String, value: Binding<Double>, color: Color, band: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 35, alignment: .leading)
            Slider(value: value, in: -12...12)
                .tint(color)
                .onChange(of: value.wrappedValue) { _, new in
                    coordinator.audioEngine.setChannelEQ(id, band: band, gain: Float(new))
                }
            Text(String(format: "%+.0f", value.wrappedValue))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var panLabel: String {
        let p = pan
        if abs(p) < 0.05 { return "C" }
        if p < 0 { return "L\(Int(abs(p) * 100))" }
        return "R\(Int(p * 100))"
    }
}
