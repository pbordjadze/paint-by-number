import Foundation
import PaintCore

/// Tiny additive synthesizer for the feedback sounds.
nonisolated enum ToneSynth {
    /// Plucked-tine tone: fundamental with a bright, fast-decaying inharmonic partial and a
    /// soft "wet" noise onset (the brush touching the canvas).
    static func kalimba(frequency f: Double, sampleRate sr: Double) -> [Float] {
        let n = Int(sr * 0.9)
        var out = [Float](repeating: 0, count: n)
        var noise = SplitMix64(seed: UInt64(f * 1000))
        var lowpassed: Double = 0
        for i in 0..<n {
            let t = Double(i) / sr
            let attack = min(1, t / 0.003)
            let body = sin(2 * .pi * f * t) * exp(-t * 5.5)
            let octave = 0.18 * sin(2 * .pi * 2 * f * t) * exp(-t * 9)
            let tine = 0.22 * sin(2 * .pi * 5.4 * f * t) * exp(-t * 28)
            let bits: UInt64 = noise.next()
            lowpassed += 0.25 * (Double(bits >> 11) / Double(1 << 53) * 2 - 1 - lowpassed)
            let brush = 0.10 * lowpassed * exp(-t * 45)
            out[i] = Float(attack * (body + octave + tine) + brush) * 0.55
        }
        return out
    }

    /// Muted wooden "thock" for a wrong-color tap.
    static func thud(sampleRate sr: Double) -> [Float] {
        let n = Int(sr * 0.18)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let pitch = 180 * (1 - 0.25 * min(1, t / 0.08))
            let attack = min(1, t / 0.002)
            out[i] = Float(attack * sin(2 * .pi * pitch * t) * exp(-t * 32)) * 0.6
        }
        return out
    }
}
