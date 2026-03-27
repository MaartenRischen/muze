// Jammerman — Mixer Panel
// Horizontal scrolling channel strips with faders, M/S buttons
// Tap channel header for detail view (EQ, sends, pan)

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
        let vol = coordinator.audioEngine.channelVolumes[id] ?? -10
        let muted = id == "master" ? false : coordinator.audioEngine.isMuted(id)
        let stripWidth: CGFloat = (UIScreen.main.bounds.width - 20) / 7.5

        return VStack(spacing: 0) {
            // Header
            Button { detailChannel = id } label: {
                Text(name)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(color)
            }

            // Fader area
            ZStack {
                // Track
                Rectangle().fill(.white.opacity(0.05))

                // Colored fill from bottom
                GeometryReader { geo in
                    let pct = CGFloat((vol + 60) / 66) // -60 to +6 dB
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(color.opacity(muted ? 0.1 : 0.3))
                            .frame(height: geo.size.height * max(0, min(1, pct)))
                    }
                }

                // Fader thumb
                GeometryReader { geo in
                    let pct = CGFloat((vol + 60) / 66)
                    let y = geo.size.height * (1 - max(0, min(1, pct)))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.7))
                        .frame(width: stripWidth * 0.6, height: 8)
                        .position(x: geo.size.width / 2, y: y)
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let geo = UIScreen.main.bounds // approximate
                    let pct = 1 - Float(v.location.y / 220)
                    let db = -60 + max(0, min(1, pct)) * 66
                    if id != "master" {
                        coordinator.audioEngine.setChannelVolume(id, db: db)
                    }
                })
            }
            .frame(height: 200)

            // dB value
            Text("\(Int(vol))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.vertical, 2)

            // Pan dot
            Circle()
                .fill(.white.opacity(0.3))
                .frame(width: 8, height: 8)

            // M / S buttons
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
                Button { /* TODO: solo */ } label: {
                    Text("S")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: stripWidth * 0.4, height: 22)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.bottom, 8)
        }
        .frame(width: stripWidth)
    }

    // MARK: - Channel Detail

    private func channelDetail(_ id: String) -> some View {
        let name = channels.first(where: { $0.1 == id })?.0 ?? id
        let color = channels.first(where: { $0.1 == id })?.2 ?? .white

        return VStack(spacing: 12) {
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

            // EQ section
            VStack(alignment: .leading, spacing: 8) {
                Text("E Q U A L I Z E R")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(2)

                HStack(spacing: 24) {
                    eqBand("LOW", value: 0)
                    eqBand("MID", value: 0)
                    eqBand("HIGH", value: 0)
                }
                .frame(maxWidth: .infinity)
            }

            // Sends
            VStack(alignment: .leading, spacing: 8) {
                Text("S E N D S")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(2)

                sendRow("REVERB", value: 0, color: color)
                sendRow("DELAY", value: 0, color: color)
            }

            // Pan
            VStack(alignment: .leading, spacing: 8) {
                Text("P A N")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(2)

                HStack {
                    Slider(value: .constant(0.5), in: 0...1)
                        .tint(.white.opacity(0.3))
                    Text("C")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(height: 350)
    }

    private func eqBand(_ label: String, value: Float) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            // Vertical slider representation
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.08)).frame(width: 8, height: 100)
                RoundedRectangle(cornerRadius: 3).fill(.blue.opacity(0.5)).frame(width: 8, height: 50).offset(y: 25)
                RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 20, height: 6)
            }
            .frame(height: 100)
            Text("0 dB")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func sendRow(_ label: String, value: Float, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            HStack {
                Circle().fill(color.opacity(0.5)).frame(width: 12, height: 12)
                Slider(value: .constant(Float(0)), in: 0...1).tint(color)
                Text("0%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
