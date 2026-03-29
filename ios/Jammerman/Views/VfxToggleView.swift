// Muze — VFX Toggle Buttons + Detail Panel
// Left-side effect toggles with long-press parameter tuning

import SwiftUI

// MARK: - VFX Toggle Button

struct VfxToggle: View {
    let label: String
    let icon: String
    @ObservedObject var param: VisualEffectParams
    let keyPath: ReferenceWritableKeyPath<VisualEffectParams, Bool>
    let color: Color
    let coordinator: TrackingCoordinator

    @State private var showDetail = false
    @State private var pressStart: Date?

    var body: some View {
        let active = param[keyPath: keyPath]

        VStack(spacing: 2) {
            Text(icon).font(.system(size: 13))
            Text(label).font(.system(size: 7, weight: .bold, design: .monospaced))
        }
        .frame(width: 42, height: 42)
        .background(active ? color.opacity(0.2) : .white.opacity(0.04))
        .foregroundStyle(active ? color : .white.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
            active ? color.opacity(0.4) : .white.opacity(0.06), lineWidth: 1))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if pressStart == nil { pressStart = Date() } }
                .onEnded { v in
                    let held = Date().timeIntervalSince(pressStart ?? Date())
                    let dist = sqrt(v.translation.width * v.translation.width + v.translation.height * v.translation.height)
                    if held > 0.4 && dist < 15 {
                        showDetail = true
                    } else {
                        param[keyPath: keyPath].toggle()
                    }
                    pressStart = nil
                }
        )
        .fullScreenCover(isPresented: $showDetail) {
            VfxDetailView(label: label, color: color, param: param, keyPath: keyPath, isPresented: $showDetail)
        }
    }
}

// MARK: - VFX Detail View

struct VfxDetailView: View {
    let label: String
    let color: Color
    @ObservedObject var param: VisualEffectParams
    let keyPath: ReferenceWritableKeyPath<VisualEffectParams, Bool>
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Text("\(label) PARAMS").font(.system(size: 18, weight: .black, design: .monospaced)).foregroundStyle(color)
                        Spacer()
                        Toggle("", isOn: Binding(get: { param[keyPath: keyPath] }, set: { param[keyPath: keyPath] = $0 }))
                            .tint(color).labelsHidden()
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark").foregroundStyle(.white.opacity(0.6))
                                .frame(width: 32, height: 32).background(.white.opacity(0.1)).clipShape(Circle())
                        }
                    }

                    // Per-effect parameters
                    Group {
                        switch label {
                        case "RING":  ringParams
                        case "HALO":  haloParams
                        case "IRIS":  irisParams
                        case "PTS":   particleParams
                        case "ARP":   arpParams
                        case "TRAIL": trailParams
                        case "SEG":   segParams
                        case "ARC":   arcParams
                        case "GEO":   geoParams
                        default: Text("No params").foregroundStyle(.white.opacity(0.3))
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Per-Effect Param Sections

    @ViewBuilder private var ringParams: some View {
        pSlider("Radius", val: $param.ringRadius, range: 0.05...0.5, fmt: "%.2f")
        pSlider("Wobble", val: $param.ringWobble, range: 0...3, fmt: "%.1f")
        pSlider("Glow Width", val: $param.ringGlowWidth, range: 2...30, fmt: "%.0f")
        pSlider("Core Width", val: $param.ringCoreWidth, range: 0.2...4, fmt: "%.1f")
        pSlider("Core Alpha", val: $param.ringAlpha, range: 0.1...1, fmt: "%.2f")
    }

    @ViewBuilder private var haloParams: some View {
        pSlider("Offset Y", val: $param.haloOffsetY, range: 0.05...0.4, fmt: "%.2f")
        pSlider("Size", val: $param.haloSize, range: 0.2...1.5, fmt: "%.2f")
        pSlider("Ambient Alpha", val: $param.haloAlpha, range: 0.05...0.8, fmt: "%.2f")
        pSlider("Inner Alpha", val: $param.haloInnerAlpha, range: 0.1...1, fmt: "%.2f")
        pSlider("Flash Alpha", val: $param.haloFlashAlpha, range: 0.1...1, fmt: "%.2f")
    }

    @ViewBuilder private var irisParams: some View {
        pSlider("Size", val: $param.irisSize, range: 2...30, fmt: "%.0f")
        pSlider("Alpha", val: $param.irisAlpha, range: 0.1...1, fmt: "%.2f")
        pSlider("Beat Pulse", val: $param.irisPulse, range: 0...4, fmt: "%.1f")
    }

    @ViewBuilder private var particleParams: some View {
        pSliderInt("Max Count", val: $param.particleCount, range: 10...200)
        pSlider("Size Mult", val: $param.particleSize, range: 0.5...8, fmt: "%.1f")
        pSlider("Alpha", val: $param.particleAlpha, range: 0.1...1, fmt: "%.2f")
        pSlider("Spawn Rate", val: $param.particleSpawnRate, range: 1...30, fmt: "%.0f")
    }

    @ViewBuilder private var arpParams: some View {
        pSlider("Glow Size", val: $param.arpGlowSize, range: 4...30, fmt: "%.0f")
        pSlider("Dot Size", val: $param.arpDotSize, range: 1...8, fmt: "%.1f")
        pSlider("Column Height", val: $param.arpColumnHeight, range: 100...500, fmt: "%.0f")
    }

    @ViewBuilder private var trailParams: some View {
        pSlider("Core Width", val: $param.trailCoreWidth, range: 1...12, fmt: "%.1f")
        pSlider("Glow Mult", val: $param.trailGlowMult, range: 0.5...5, fmt: "%.1f")
        pSlider("Core Alpha", val: $param.trailCoreAlpha, range: 0.1...1, fmt: "%.2f")
        pSlider("Glow Alpha", val: $param.trailGlowAlpha, range: 0.05...0.8, fmt: "%.2f")
        pSlider("Decay", val: $param.trailDecay, range: 0.9...0.999, fmt: "%.3f")
    }

    @ViewBuilder private var segParams: some View {
        pSlider("Darken", val: $param.segDarkenAlpha, range: 0...1, fmt: "%.2f")
        pSlider("Feather", val: $param.segFeather, range: -30...30, fmt: "%.0f")
        pSlider("Scale X", val: $param.segScaleX, range: 0.3...2, fmt: "%.2f")
        pSlider("Scale Y", val: $param.segScaleY, range: 0.3...2, fmt: "%.2f")
        pSlider("Edge Low", val: $param.segEdgeLow, range: 0...0.5, fmt: "%.2f")
        pSlider("Edge High", val: $param.segEdgeHigh, range: 0.5...1, fmt: "%.2f")
    }

    @ViewBuilder private var arcParams: some View {
        pSlider("Bar Width", val: $param.freqArcBarWidth, range: 1...12, fmt: "%.0f")
        pSlider("Max Height", val: $param.freqArcHeight, range: 10...100, fmt: "%.0f")
        pSlider("Arc Radius", val: $param.freqArcRadius, range: 0.1...0.6, fmt: "%.2f")
        pSlider("Y Position", val: $param.freqArcY, range: 0.7...0.98, fmt: "%.2f")
    }

    @ViewBuilder private var geoParams: some View {
        pSlider("Alpha", val: $param.modeGeoAlpha, range: 0.005...0.1, fmt: "%.3f")
    }

    // MARK: - Slider Helpers

    private func pSlider(_ label: String, val: Binding<Float>, range: ClosedRange<Float>, fmt: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5)).frame(width: 80, alignment: .leading)
            Slider(value: Binding(get: { Double(val.wrappedValue) }, set: { val.wrappedValue = Float($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .tint(color)
            Text(String(format: fmt, val.wrappedValue))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.7)).frame(width: 40, alignment: .trailing)
        }
    }

    private func pSliderInt(_ label: String, val: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5)).frame(width: 80, alignment: .leading)
            Slider(value: Binding(get: { Double(val.wrappedValue) }, set: { val.wrappedValue = Int($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .tint(color)
            Text("\(val.wrappedValue)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color.opacity(0.7)).frame(width: 40, alignment: .trailing)
        }
    }
}
