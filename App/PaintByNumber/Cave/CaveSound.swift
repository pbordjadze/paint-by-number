#if UNRELEASED
import AVFoundation
import CoreHaptics
import Foundation
import PaintCore
import os

/// The cave's sound and touch (painting-company row 371), all synthesized on the device, no
/// audio files and no microphone (Paul: never). The passage is a space: an environment node
/// places each sound where it is on the wall around the listener at the screen's middle, and a
/// large hall's reverb carries them all. The torch crackles and breathes where the torch is;
/// water drips somewhere in the dark now and then, never twice in one place; the blow is a soft
/// breath at the finger; an area settling is a low hollow tap, and the finished painting's flare
/// a rush of air. Haptics follow: a soft continuous rumble while pigment is blown, a tick as an
/// area settles, a slow swell for the flare.
///
/// Everything runs on `queue` (starting an engine blocks its caller). It plays only with the
/// app's sounds and haptics settings on, mixes with other audio and keeps to the silent switch.
nonisolated final class CaveSound: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pbordjadze.paintbynumber.cave", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let space = AVAudioEnvironmentNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let fire = AVAudioPlayerNode()
    private let breath = AVAudioPlayerNode()
    private let drips = (0..<3).map { _ in AVAudioPlayerNode() }
    private let taps = AVAudioPlayerNode()
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var isRunning = false
    private var isBuilt = false
    private var nextDrip = 0
    /// Bumped by each start, so a drip waiting from before a stop doesn't run on beside the new ones.
    private var dripRun = 0
    private var haptics: CHHapticEngine?
    private var rumble: (any CHHapticAdvancedPatternPlayer)?
    private let soundsOn: Bool
    private let hapticsOn: Bool

    init(sounds: Bool, haptics: Bool) {
        soundsOn = sounds
        hapticsOn = haptics && CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// The app's settings for sounds and haptics.
    @MainActor
    static func fromSettings(_ defaults: UserDefaults = .standard) -> CaveSound {
        CaveSound(sounds: defaults.object(forKey: SettingsKey.sounds) as? Bool ?? SettingsDefault.sounds,
                  haptics: defaults.object(forKey: SettingsKey.haptics) as? Bool ?? SettingsDefault.haptics)
    }

    func start() {
        queue.async { [self] in
            startAudio()
            startHaptics()
            dripRun += 1
            scheduleDrip(run: dripRun)
        }
    }

    func stop() {
        queue.async { [self] in
            isRunning = false
            fire.stop()
            breath.stop()
            engine.stop()
            rumble = nil
            haptics?.stop()
            haptics = nil
        }
    }

    // MARK: - What happens

    /// Where the torch is and where the listener stands (wall points): each sound placed by them.
    func place(torch: SIMD2<Float>, listener: SIMD2<Float>) {
        queue.async { [self] in
            guard isRunning else { return }
            fire.position = Self.position(torch, from: listener)
            breath.position = Self.position(torch + SIMD2(0, 60), from: listener)
        }
    }

    func blow(_ on: Bool) {
        queue.async { [self] in
            if isRunning {
                breath.volume = on ? 0.5 : 0
            }
            guard hapticsOn, let haptics else { return }
            do {
                if on {
                    if rumble == nil {
                        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.22),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08),
                        ], relativeTime: 0, duration: 30)
                        let player = try haptics.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                        player.loopEnabled = true
                        rumble = player
                    }
                    try rumble?.start(atTime: CHHapticTimeImmediate)
                } else {
                    try rumble?.stop(atTime: CHHapticTimeImmediate)
                }
            } catch {
                Log.feedback.error("The cave's rumble failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func lift() { transient(intensity: 0.35, sharpness: 0.2) }
    func pick() {
        transient(intensity: 0.3, sharpness: 0.5)
        play("tap", on: taps, volume: 0.25)
    }

    func settle() {
        transient(intensity: 0.55, sharpness: 0.3)
        play("tap", on: taps, volume: 0.5)
    }

    func finish() {
        swell()
        play("rush", on: taps, volume: 0.6)
    }

    // MARK: - On the queue

    private static func position(_ p: SIMD2<Float>, from listener: SIMD2<Float>) -> AVAudio3DPoint {
        AVAudio3DPoint(x: (p.x - listener.x) / 120, y: -(p.y - listener.y) / 120, z: -1.5)
    }

    private func startAudio() {
        guard soundsOn, !isRunning else { return }
        if !isBuilt {
            for buffer in ["fire": Self.fire, "breath": Self.breath, "drip": Self.drip, "tap": Self.tap, "rush": Self.rush] {
                buffers[buffer.key] = make(buffer.value(format.sampleRate))
            }
            engine.attach(space)
            engine.connect(space, to: engine.mainMixerNode, format: nil)
            space.reverbParameters.enable = true
            space.reverbParameters.loadFactoryReverbPreset(.largeHall2)
            space.reverbParameters.level = -6
            space.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
            for node in [fire, breath, taps] + drips {
                engine.attach(node)
                engine.connect(node, to: space, format: format)
                node.renderingAlgorithm = .HRTFHQ
                node.reverbBlend = 0.45
            }
            taps.reverbBlend = 0.6
            for drip in drips { drip.reverbBlend = 0.8 }
            // A route change (headphones out) or an interruption (a call) stops the engine under
            // us: start it again once it may play.
            let center = NotificationCenter.default
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.restartAudio() }
            }
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                guard type == .ended, let self else { return }
                self.queue.async { self.restartAudio() }
            }
            isBuilt = true
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            engine.prepare()
            try engine.start()
            if let fireBuffer = buffers["fire"] { fire.scheduleBuffer(fireBuffer, at: nil, options: .loops) }
            if let breathBuffer = buffers["breath"] { breath.scheduleBuffer(breathBuffer, at: nil, options: .loops) }
            fire.volume = 0.5
            breath.volume = 0
            for node in [fire, breath, taps] + drips { node.play() }
            isRunning = true
        } catch {
            Log.feedback.error("The cave's sounds are unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    /// After the engine stopped on its own: everything played again from the start, if it was playing.
    private func restartAudio() {
        guard isRunning else { return }
        isRunning = false
        for node in [fire, breath, taps] + drips { node.stop() }
        engine.stop()
        startAudio()
        guard isRunning else { return }
        dripRun += 1
        scheduleDrip(run: dripRun)
    }

    private func startHaptics() {
        guard hapticsOn, haptics == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            // A reset engine (the app sent to the background, a server restart) starts again on
            // the next use; the rumble's player went with it.
            engine.resetHandler = { [weak self] in
                guard let self else { return }
                self.queue.async {
                    self.rumble = nil
                    try? self.haptics?.start()
                }
            }
            try engine.start()
            haptics = engine
        } catch {
            Log.feedback.error("The cave's haptics are unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    /// Water dripping somewhere in the dark, every few seconds, placed at random about the listener.
    private func scheduleDrip(run: Int) {
        let wait = Double.random(in: 2.5...7)
        queue.asyncAfter(deadline: .now() + wait) { [self] in
            guard run == dripRun, isRunning, let buffer = buffers["drip"] else { return }
            let node = drips[nextDrip % drips.count]
            nextDrip += 1
            node.position = AVAudio3DPoint(x: Float.random(in: -4...4), y: Float.random(in: -1...2.5), z: -Float.random(in: 1.5...5))
            node.volume = Float.random(in: 0.25...0.6)
            node.scheduleBuffer(buffer, at: nil, options: .interrupts)
            scheduleDrip(run: run)
        }
    }

    private func play(_ name: String, on node: AVAudioPlayerNode, volume: Float) {
        queue.async { [self] in
            guard isRunning, let buffer = buffers[name] else { return }
            node.volume = volume
            node.position = AVAudio3DPoint(x: 0, y: -1, z: -1)
            node.scheduleBuffer(buffer, at: nil, options: [])
        }
    }

    private func transient(intensity: Float, sharpness: Float) {
        queue.async { [self] in
            guard let haptics else { return }
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0)
            try? haptics.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(atTime: CHHapticTimeImmediate)
        }
    }

    private func swell() {
        queue.async { [self] in
            guard let haptics else { return }
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
            ], relativeTime: 0, duration: 2.2)
            let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.1),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.9, value: 1),
                CHHapticParameterCurve.ControlPoint(relativeTime: 2.2, value: 0),
            ], relativeTime: 0)
            try? haptics.makePlayer(with: CHHapticPattern(events: [event], parameterCurves: [curve])).start(atTime: CHHapticTimeImmediate)
        }
    }

    private func make(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    // MARK: - Synthesis

    /// A few seconds of fire to loop: a low roar of filtered noise and crackles, each a short burst
    /// of bright noise dying away, at random, ends faded so the loop is seamless.
    static func fire(_ rate: Double) -> [Float] {
        var random = SplitMix64(seed: 15_000)
        let n = Int(rate * 4)
        var out = [Float](repeating: 0, count: n)
        var low: Float = 0, lower: Float = 0
        for i in 0..<n {
            let white = random.nextFloat() * 2 - 1
            low += (white - low) * 0.02
            lower += (low - lower) * 0.05
            out[i] = lower * 0.9
        }
        var at = 0
        while at < n {
            at += Int(rate * Double(0.02 + random.nextFloat() * 0.16))
            let length = Int(rate * Double(0.002 + random.nextFloat() * 0.008))
            let loud = 0.15 + random.nextFloat() * 0.45
            var last: Float = 0
            for k in 0..<length where at + k < n {
                let white = random.nextFloat() * 2 - 1
                let bright = white - last
                last = white
                out[at + k] += bright * loud * exp(-Float(k) / Float(max(1, length / 3)))
            }
        }
        let fade = Int(rate * 0.05)
        for k in 0..<fade {
            let g = Float(k) / Float(fade)
            out[k] *= g
            out[n - 1 - k] *= g
        }
        return out
    }

    /// A breath through a hollow bone, to loop: noise between two low-pass filters, swelling slowly.
    static func breath(_ rate: Double) -> [Float] {
        var random = SplitMix64(seed: 17_000)
        let n = Int(rate * 3)
        var out = [Float](repeating: 0, count: n)
        var a: Float = 0, b: Float = 0
        for i in 0..<n {
            let white = random.nextFloat() * 2 - 1
            a += (white - a) * 0.16
            b += (white - b) * 0.04
            let t = Float(i) / Float(n)
            out[i] = (a - b) * 0.6 * (0.8 + 0.2 * sin(t * 2 * .pi * 2))
        }
        let fade = Int(rate * 0.08)
        for k in 0..<fade {
            let g = Float(k) / Float(fade)
            out[k] *= g
            out[n - 1 - k] *= g
        }
        return out
    }

    /// A drop of water: a tone rising fast as the bubble closes, ringing a moment.
    static func drip(_ rate: Double) -> [Float] {
        let n = Int(rate * 0.35)
        var out = [Float](repeating: 0, count: n)
        var phase: Double = 0
        for i in 0..<n {
            let t = Double(i) / rate
            let f = 1000 + 1600 * min(1, t / 0.03)
            phase += 2 * .pi * f / rate
            out[i] = Float(sin(phase) * exp(-t / 0.05) * 0.5)
        }
        return out
    }

    /// A low hollow tap, as of a palm on the rock.
    static func tap(_ rate: Double) -> [Float] {
        var random = SplitMix64(seed: 19_000)
        let n = Int(rate * 0.4)
        var out = [Float](repeating: 0, count: n)
        var low: Float = 0
        for i in 0..<n {
            let t = Double(i) / rate
            let white = random.nextFloat() * 2 - 1
            low += (white - low) * 0.1
            out[i] = Float(sin(2 * .pi * 95 * t) * exp(-t / 0.09)) * 0.6 + low * Float(exp(-t / 0.02)) * 0.5
        }
        return out
    }

    /// A rush of air, swelling and falling: the flare, and the way out.
    static func rush(_ rate: Double) -> [Float] {
        var random = SplitMix64(seed: 21_000)
        let n = Int(rate * 2.2)
        var out = [Float](repeating: 0, count: n)
        var a: Float = 0, b: Float = 0
        for i in 0..<n {
            let white = random.nextFloat() * 2 - 1
            let t = Float(i) / Float(n)
            let open = 0.05 + 0.25 * sin(t * .pi)
            a += (white - a) * open
            b += (a - b) * 0.02
            out[i] = (a - b) * sin(t * .pi) * 0.7
        }
        return out
    }
}
#endif
