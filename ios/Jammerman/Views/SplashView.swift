// Jammerman — Splash/Title Screen
// Animated "JAMMER MAN" -> "JAMMERMAN" with staggered letter animation
// Mirrors web's splash screen

import SwiftUI

struct SplashView: View {
    @Binding var showSplash: Bool

    @State private var letterOffsets: [CGFloat] = Array(repeating: 30, count: 9)
    @State private var letterOpacities: [Double] = Array(repeating: 0, count: 9)
    @State private var taglineOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonGlowScale: CGFloat = 1.0
    @State private var collapsed = false

    private let letters = ["J", "A", "M", "M", "E", "R", "M", "A", "N"]
    private let spacedText = "J A M M E R   M A N"

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Subtle gradient glow
            RadialGradient(
                colors: [Color(hex: "e8a948").opacity(0.15), .clear],
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Title
                HStack(spacing: collapsed ? 0 : 4) {
                    ForEach(0..<9, id: \.self) { i in
                        let isSpace = (!collapsed && i == 6)
                        if !collapsed && i == 6 {
                            Text(" ")
                                .font(.system(size: 38, weight: .black, design: .monospaced))
                                .frame(width: 12)
                        }
                        Text(letters[i])
                            .font(.system(size: 38, weight: .black, design: .monospaced))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "e8a948"), Color(hex: "f59e0b")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .offset(y: letterOffsets[i])
                            .opacity(letterOpacities[i])
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: collapsed)

                // Tagline
                Text("Your body is the instrument")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 16)
                    .opacity(taglineOpacity)

                Spacer()

                // Begin button
                Button {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showSplash = false
                    }
                } label: {
                    ZStack {
                        // Glow ring
                        Circle()
                            .stroke(Color(hex: "e8a948").opacity(0.3), lineWidth: 2)
                            .frame(width: 100, height: 100)
                            .scaleEffect(buttonGlowScale)

                        Circle()
                            .stroke(Color(hex: "e8a948").opacity(0.15), lineWidth: 1)
                            .frame(width: 120, height: 120)
                            .scaleEffect(buttonGlowScale * 1.1)

                        // Button
                        Text("BEGIN")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: "e8a948"))
                            .frame(width: 80, height: 80)
                            .background(Color(hex: "e8a948").opacity(0.1))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "e8a948").opacity(0.5), lineWidth: 1.5)
                            )
                    }
                }
                .opacity(buttonOpacity)

                Spacer()
                    .frame(height: 80)
            }
        }
        .onAppear {
            animateEntrance()
        }
    }

    private func animateEntrance() {
        // Staggered letter animation
        for i in 0..<9 {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(i) * 0.06)) {
                letterOffsets[i] = 0
                letterOpacities[i] = 1
            }
        }

        // Collapse "JAMMER MAN" -> "JAMMERMAN" after letters appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                collapsed = true
            }
        }

        // Tagline fade in
        withAnimation(.easeIn(duration: 0.6).delay(1.2)) {
            taglineOpacity = 1
        }

        // Button fade in
        withAnimation(.easeIn(duration: 0.6).delay(1.6)) {
            buttonOpacity = 1
        }

        // Button glow pulse animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                buttonGlowScale = 1.15
            }
        }
    }
}
