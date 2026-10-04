import AVFoundation
import Foundation

/// Soft, musical feedback sounds, synthesized the first time they're needed (when a painting
/// screen first appears, or at the first sound; no audio assets).
///
/// Painting plays one tune (`PaintingMelody`), a note per fill whatever the color, on a
/// pentatonic scale so its kalimba-like notes can never clash. Uses the ambient session
/// category: it mixes with the user's music and respects the silent switch.
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var notes: [AVAudioPCMBuffer] = []
    private var thud: AVAudioPCMBuffer?
    private var isSetUp = false
    private var lastNote: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var melody = PaintingMelody()

    /// C major pentatonic over two octaves from C4.
    static let scale: [Double] = [261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66]

    func prepare() { _ = setUpIfNeeded() }

    /// The tune's next note. `velocity` 0…1.
    func paint(velocity: Float) {
        let now = clock.now
        if let last = lastNote, now - last < .milliseconds(40) { return }
        lastNote = now
        guard setUpIfNeeded() else { return }
        play(notes[melody.next(at: now)], volume: 0.18 + 0.22 * min(max(velocity, 0), 1))
    }

    func reject() {
        guard setUpIfNeeded(), let thud else { return }
        play(thud, volume: 0.35)
    }

    /// A little rising arpeggio from the tune's latest note.
    func colorComplete() {
        guard setUpIfNeeded() else { return }
        let root = min(melody.latest, notes.count - 5)
        for (k, step) in [0, 2, 4].enumerated() {
            play(notes[root + step], volume: 0.3, delay: 0.12 + 0.085 * Double(k))
        }
    }

    func celebrate() {
        guard setUpIfNeeded() else { return }
        for i in 0..<notes.count {
            play(notes[i], volume: 0.22 + 0.01 * Float(i), delay: 0.07 * Double(i))
        }
        for i in [5, 7, 9, 11] {
            play(notes[i], volume: 0.28, delay: 0.07 * Double(notes.count) + 0.12)
        }
    }

    // MARK: Engine

    private func setUpIfNeeded() -> Bool {
        if isSetUp {
            if !engine.isRunning { try? engine.start() }
            return engine.isRunning
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            for _ in 0..<10 {
                let voice = AVAudioPlayerNode()
                engine.attach(voice)
                engine.connect(voice, to: engine.mainMixerNode, format: format)
                voices.append(voice)
            }
            engine.mainMixerNode.outputVolume = 0.8
            engine.prepare()
            try engine.start()
            for voice in voices { voice.play() }
            notes = Self.scale.map { buffer(ToneSynth.kalimba(frequency: $0, sampleRate: format.sampleRate)) }
            thud = buffer(ToneSynth.thud(sampleRate: format.sampleRate))
            isSetUp = true
            return true
        } catch {
            return false
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float, delay: TimeInterval = 0) {
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = volume
        if delay > 0, let nodeTime = voice.lastRenderTime, let playerTime = voice.playerTime(forNodeTime: nodeTime) {
            let start = AVAudioTime(
                sampleTime: playerTime.sampleTime + AVAudioFramePosition(delay * format.sampleRate),
                atRate: format.sampleRate)
            voice.scheduleBuffer(buffer, at: start, options: [], completionHandler: nil)
        } else {
            voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        }
        if !voice.isPlaying { voice.play() }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
