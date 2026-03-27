// Jammerman — Main Performance View
// Full-screen camera with instrument toggles overlay + mode HUD

import SwiftUI

struct PerformanceView: View {
    @ObservedObject var coordinator: TrackingCoordinator

    @State private var padActive = false
    @State private var arpActive = false
    @State private var melActive = false
    @State private var beatActive = false

    var body: some View {
        ZStack {
            // Full-screen camera
            CameraPreview(session: coordinator.camera.captureSession)
                .ignoresSafeArea()

            // Mode HUD (top center)
            VStack {
                modeHUD
                    .padding(.top, 60)
                Spacer()
            }

            // Instrument toggles (right side)
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    toggleButton(label: "PAD", icon: "◈", active: $padActive, channel: "pad", color: .purple)
                    toggleButton(label: "ARP", icon: "♪", active: $arpActive, channel: "arp", color: .cyan)
                    toggleButton(label: "MEL", icon: "🎵", active: $melActive, channel: "melody", color: .green)
                    toggleButton(label: "BEAT", icon: "◉", active: $beatActive, channel: "beat", color: .orange)
                }
                .padding(.trailing, 16)
            }

            // Face detection indicator
            VStack {
                Spacer()
                HStack {
                    Circle()
                        .fill(coordinator.state.faceDetected ? Color.green : Color.red.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(coordinator.state.faceDetected ? "Face" : "No face")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))

                    if coordinator.state.handPresent {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text(coordinator.state.handOpen ? "Open" : "Fist")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    Text("v1.1.1")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
        .statusBarHidden()
    }

    // MARK: - Mode HUD

    private var modeHUD: some View {
        VStack(spacing: 4) {
            Text(coordinator.state.currentModeName.uppercased())
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)

            // Valence bar
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

    // MARK: - Toggle Buttons

    private func toggleButton(label: String, icon: String, active: Binding<Bool>, channel: String, color: Color) -> some View {
        Button {
            active.wrappedValue.toggle()
            coordinator.toggleMute(channel)
        } label: {
            VStack(spacing: 2) {
                Text(icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .frame(width: 52, height: 52)
            .background(active.wrappedValue ? color.opacity(0.8) : .white.opacity(0.1))
            .foregroundStyle(active.wrappedValue ? .white : .white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(active.wrappedValue ? color : .white.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Accent Color

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
