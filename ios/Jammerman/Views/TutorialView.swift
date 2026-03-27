// Jammerman — Tutorial Overlay
// "LEARN JAMMERMAN" with 4 tutorial tracks
// "First Touch" has full 5-step tutorial content

import SwiftUI

struct TutorialView: View {
    @Binding var isPresented: Bool
    @State private var activeTutorial: String? = nil
    @State private var currentStep: Int = 0

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    if activeTutorial != nil {
                        activeTutorial = nil
                        currentStep = 0
                    } else {
                        isPresented = false
                    }
                }

            if let tutorial = activeTutorial {
                tutorialContent(tutorial)
            } else {
                tutorialMenu
            }
        }
    }

    // MARK: - Tutorial Menu

    private var tutorialMenu: some View {
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
                tutorialCard("First Touch", subtitle: "Make music in 30 seconds", id: "first-touch")
                tutorialCard("Exploring", subtitle: "All face, hand & touch controls", id: "exploring")
                tutorialCard("Sound Design", subtitle: "Synths, mixer, presets & scales", id: "sound-design")
                tutorialCard("Performance", subtitle: "Loops, scenes & live techniques", id: "performance")
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

    private func tutorialCard(_ title: String, subtitle: String, id: String) -> some View {
        Button {
            activeTutorial = id
            currentStep = 0
        } label: {
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

    // MARK: - Tutorial Content

    private func tutorialContent(_ id: String) -> some View {
        let steps = tutorialSteps(for: id)
        let step = steps[min(currentStep, steps.count - 1)]

        return VStack(spacing: 20) {
            Spacer()

            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentStep ? Color(hex: "e8a948") : .white.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }

            // Step number
            Text("STEP \(currentStep + 1) of \(steps.count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "e8a948").opacity(0.7))
                .tracking(2)

            // Title
            Text(step.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Icon
            Text(step.icon)
                .font(.system(size: 60))
                .padding(.vertical, 8)

            // Description
            Text(step.description)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)

            // Tip
            if !step.tip.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow.opacity(0.7))
                        .font(.system(size: 12))
                    Text(step.tip)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(12)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            // Navigation buttons
            HStack(spacing: 20) {
                if currentStep > 0 {
                    Button {
                        withAnimation { currentStep -= 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if currentStep < steps.count - 1 {
                    Button {
                        withAnimation { currentStep += 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "e8a948"))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: "e8a948").opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: "e8a948").opacity(0.3), lineWidth: 1)
                        )
                    }
                } else {
                    Button {
                        activeTutorial = nil
                        currentStep = 0
                        isPresented = false
                    } label: {
                        Text("Done!")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.green.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.green.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }

            // Close
            Button {
                activeTutorial = nil
                currentStep = 0
            } label: {
                Text("exit tutorial")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 30)
    }

    // MARK: - Tutorial Steps Data

    struct TutorialStep {
        let title: String
        let icon: String
        let description: String
        let tip: String
    }

    private func tutorialSteps(for id: String) -> [TutorialStep] {
        switch id {
        case "first-touch":
            return firstTouchSteps
        case "exploring":
            return exploringSteps
        case "sound-design":
            return soundDesignSteps
        case "performance":
            return performanceSteps
        default:
            return firstTouchSteps
        }
    }

    private var firstTouchSteps: [TutorialStep] {
        [
            TutorialStep(
                title: "Face the Camera",
                icon: "O",
                description: "Hold your phone at arm's length and look at the screen. Jammerman tracks your face to control the music. When your face is detected, the pad and arp synths will start playing automatically.",
                tip: "Make sure your face is well-lit and centered on screen."
            ),
            TutorialStep(
                title: "Tap an Instrument On",
                icon: "~",
                description: "On the right side of the screen, tap PAD to unmute the pad synth. You'll hear warm chords that follow your facial expression. Tap ARP to add an arpeggio. Tap BEAT for drums.",
                tip: "Long-press any toggle to adjust its volume."
            ),
            TutorialStep(
                title: "Smile to Change the Mood",
                icon: ":)",
                description: "Your expression controls the musical mode. Smile for bright, happy sounds (Lydian/Ionian). Relax your face for mellow tones (Dorian). Frown for dark, moody music (Phrygian).",
                tip: "Watch the mode name change at the top of the screen."
            ),
            TutorialStep(
                title: "Raise Your Hand to Play Melody",
                icon: "#",
                description: "Tap MEL to enable the melody synth, then raise your hand in front of the camera. Move it up and down to play notes. The melody follows the same scale as your face expression.",
                tip: "Close your fist to re-articulate notes, open hand for legato."
            ),
            TutorialStep(
                title: "Try the Chord Bar",
                icon: "=",
                description: "Tap the chord buttons (I, ii, iii, IV, V, vi) at the bottom of the screen to change chord progressions. Each chord changes what the pad, arp, and melody play. You just made your first 30-second jam!",
                tip: "Open the settings (gear icon) to explore presets, or tap MIX to adjust levels."
            ),
        ]
    }

    private var exploringSteps: [TutorialStep] {
        [
            TutorialStep(
                title: "Head Tilt = Filter",
                icon: "/",
                description: "Tilt your head down to close the master lowpass filter (dark, muffled sound). Tilt up to open it (bright, crisp). This gives you real-time timbral control.",
                tip: "Combine with eyebrow raise for dramatic buildups."
            ),
            TutorialStep(
                title: "Eyes = Reverb",
                icon: "o",
                description: "Open your eyes wide to increase reverb on the synths. Squint or close your eyes to make the sound drier and more intimate.",
                tip: "Great for transitions between sections."
            ),
            TutorialStep(
                title: "Eyebrows = Octave",
                icon: "^",
                description: "Raise your eyebrows to shift the playing octave higher. Lower them to go down. This affects the pad voicing and arp range.",
                tip: "Combine with mode changes for maximum range."
            ),
        ]
    }

    private var soundDesignSteps: [TutorialStep] {
        [
            TutorialStep(
                title: "Presets",
                icon: "P",
                description: "Tap the gear icon and look at the PERFORM tab. Cycle through presets like Ambient Dream, Dark Techno, Lo-Fi Chill. Each preset changes BPM, synth parameters, and volumes.",
                tip: "After loading a preset, tweak individual parameters to make it yours."
            ),
            TutorialStep(
                title: "Waveform Selection",
                icon: "W",
                description: "In each synth tab (ARP, MELODY, PAD), tap the wave button to cycle through sine, triangle, sawtooth, and square waveforms. Each gives a different character.",
                tip: "Sine = smooth, Saw = bright, Square = hollow, Triangle = soft."
            ),
            TutorialStep(
                title: "Mixer",
                icon: "M",
                description: "Tap MIX in the top bar to open the mixer. Drag faders to adjust levels. Tap a channel header for detail view with EQ, reverb/delay sends, and pan control.",
                tip: "Use solo (S) to isolate a channel."
            ),
        ]
    }

    private var performanceSteps: [TutorialStep] {
        [
            TutorialStep(
                title: "Loop Recorder",
                icon: "L",
                description: "In the PERFORM tab, tap REC to start a count-in, then play melody notes. After the loop finishes, it auto-plays. Tap OVR to add more layers. Use UNDO to remove the last layer.",
                tip: "Change bar count before recording (1, 2, 4, or 8 bars)."
            ),
            TutorialStep(
                title: "Scenes",
                icon: "S",
                description: "Tap SAVE, then a scene slot (1-4) to save your current setup. Later, tap the slot to instantly recall everything: BPM, key, volumes, synth settings.",
                tip: "Great for live performance — set up 4 different vibes."
            ),
            TutorialStep(
                title: "Riser Effect",
                icon: "^",
                description: "Tap the up-arrow in the top bar to trigger a riser build. Filtered noise sweeps up while other instruments duck. After 4 seconds, it auto-drops with a big kick hit.",
                tip: "Use before chord changes for dramatic transitions."
            ),
        ]
    }
}
