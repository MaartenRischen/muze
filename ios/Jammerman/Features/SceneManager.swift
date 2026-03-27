// Jammerman — Scene Manager
// 4 scene slots that capture/recall full state with crossfade
// Mirrors web's MUZE.SceneManager (features.js)

import Foundation
import Combine

struct SceneSnapshot {
    let bpm: Double
    let rootOffset: Int
    let swing: Int
    let arpPattern: String
    let arp2Pattern: String
    let arpNoteValue: String
    let arp2NoteValue: String
    let extraScaleMode: String?
    let chordIndex: Int
    let presetIdx: Int
    let channelVolumes: [String: Float]
    let padMuted: Bool
    let arpMuted: Bool
    let arp2Muted: Bool
    let melodyMuted: Bool
    let beatMuted: Bool
    let binauralActive: Bool
    let padHarmonicity: Double
    let padModIndex: Double
    let padWaveform: WaveformType
    let arpWaveform: WaveformType
    let arp2Waveform: WaveformType
    let melodyWaveform: WaveformType
    let chordAutoAdvance: Bool
    let channelPans: [String: Float]
    let channelReverbSends: [String: Float]
    let channelDelaySends: [String: Float]
}

class SceneManager: ObservableObject {
    @Published var scenes: [SceneSnapshot?] = [nil, nil, nil, nil]
    @Published var activeSlot: Int = -1
    @Published var saveMode: Bool = false

    func toggleSaveMode() {
        saveMode.toggle()
    }

    func slotTapped(_ index: Int, coordinator: TrackingCoordinator) {
        if saveMode {
            saveScene(index, coordinator: coordinator)
            saveMode = false
        } else {
            recallScene(index, coordinator: coordinator)
        }
    }

    func saveScene(_ index: Int, coordinator: TrackingCoordinator) {
        let engine = coordinator.audioEngine
        let state = coordinator.state

        let snapshot = SceneSnapshot(
            bpm: engine.bpm,
            rootOffset: state.rootOffset,
            swing: engine.swing,
            arpPattern: engine.arpPattern,
            arp2Pattern: engine.arp2Pattern,
            arpNoteValue: engine.arpNoteValue,
            arp2NoteValue: engine.arp2NoteValue,
            extraScaleMode: state.extraScaleMode,
            chordIndex: state.chordIndex,
            presetIdx: state.presetIdx,
            channelVolumes: engine.channelVolumes,
            padMuted: engine.padMuted,
            arpMuted: engine.arpMuted,
            arp2Muted: engine.arp2Muted,
            melodyMuted: engine.melodyMuted,
            beatMuted: engine.beatMuted,
            binauralActive: engine.binauralActive,
            padHarmonicity: engine.padOsc.harmonicity,
            padModIndex: engine.padOsc.modulationIndex,
            padWaveform: engine.padOsc.waveformType,
            arpWaveform: engine.arpOsc.waveformType,
            arp2Waveform: engine.arp2Osc.waveformType,
            melodyWaveform: engine.melodyOsc.waveformType,
            chordAutoAdvance: engine.chordAutoAdvance,
            channelPans: engine.channelPans,
            channelReverbSends: engine.channelReverbSends,
            channelDelaySends: engine.channelDelaySends
        )

        scenes[index] = snapshot
        activeSlot = index
    }

    func recallScene(_ index: Int, coordinator: TrackingCoordinator) {
        guard let scene = scenes[index] else { return }

        let engine = coordinator.audioEngine
        let state = coordinator.state

        activeSlot = index

        // Apply all state with crossfade where possible
        engine.setBPM(scene.bpm)
        state.rootOffset = scene.rootOffset
        engine.swing = scene.swing
        engine.setArpPattern(scene.arpPattern)
        engine.setArp2Pattern(scene.arp2Pattern)
        engine.setArpNoteValue(scene.arpNoteValue)
        engine.setArp2NoteValue(scene.arp2NoteValue)
        state.extraScaleMode = scene.extraScaleMode
        state.chordIndex = scene.chordIndex
        state.presetIdx = scene.presetIdx

        // Channel volumes
        for (ch, vol) in scene.channelVolumes {
            engine.setChannelVolume(ch, db: vol)
        }

        // Mute states
        engine.padMuted = scene.padMuted
        engine.arpMuted = scene.arpMuted
        engine.arp2Muted = scene.arp2Muted
        engine.melodyMuted = scene.melodyMuted
        engine.beatMuted = scene.beatMuted
        engine.binauralActive = scene.binauralActive

        // Synth params
        engine.padOsc.harmonicity = scene.padHarmonicity
        engine.padOsc.modulationIndex = scene.padModIndex
        engine.padOsc.waveformType = scene.padWaveform
        engine.arpOsc.waveformType = scene.arpWaveform
        engine.arp2Osc.waveformType = scene.arp2Waveform
        engine.melodyOsc.waveformType = scene.melodyWaveform

        // Chord auto-advance
        engine.chordAutoAdvance = scene.chordAutoAdvance

        // Per-channel pan, reverb send, delay send
        for (ch, pan) in scene.channelPans {
            engine.setChannelPan(ch, pan: pan)
        }
        for (ch, send) in scene.channelReverbSends {
            engine.setChannelReverbSend(ch, amount: send)
        }
        for (ch, send) in scene.channelDelaySends {
            engine.setChannelDelaySend(ch, amount: send)
        }
    }

    func hasScene(_ index: Int) -> Bool {
        scenes[index] != nil
    }
}
