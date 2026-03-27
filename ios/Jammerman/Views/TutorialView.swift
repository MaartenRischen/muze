// Jammerman — Tutorial Overlay
// "LEARN JAMMERMAN" with 4 tutorial tracks

import SwiftUI

struct TutorialView: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 24) {
                Spacer()

                Text("L E A R N   J A M M E R M A N")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(2)

                Text("Step-by-step guides while you play")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                VStack(spacing: 14) {
                    tutorialCard("First Touch", subtitle: "Make music in 30 seconds")
                    tutorialCard("Exploring", subtitle: "All face, hand & touch controls")
                    tutorialCard("Sound Design", subtitle: "Synths, mixer, presets & scales")
                    tutorialCard("Performance", subtitle: "Loops, scenes & live techniques")
                }

                Button { isPresented = false } label: {
                    Text("cancel")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, 40)
        }
    }

    private func tutorialCard(_ title: String, subtitle: String) -> some View {
        Button { /* TODO: start tutorial */ } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
