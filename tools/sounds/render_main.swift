// The hidden modes' sounds (painting-company row 381) rendered off the device: the app's own
// synthesis (`ToneSynth`, `EraSynth`), compiled with this file by `render.sh`, written as WAV
// files with a level report, and a reel that plays them as a painter would meet them.
import Foundation

let sr = EraSynth.sampleRate
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "era-sounds")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// 16-bit mono WAV.
func write(_ samples: [Float], _ name: String) throws {
    var data = Data()
    func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8)); le(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
    le(UInt32(sr)); le(UInt32(sr * 2)); le(UInt16(2)); le(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); le(bytes)
    for s in samples { le(Int16(max(-1, min(1, s)) * 32767)) }
    try data.write(to: out.appendingPathComponent(name + ".wav"))
}

/// Peak and loudest 50 ms RMS, in dB below full scale, as the app's mixer plays it (0.8).
func level(_ samples: [Float]) -> (peak: Double, rms: Double) {
    let s = samples.map { Double($0) * 0.8 }
    let peak = s.map(abs).max() ?? 0
    let window = Int(sr * 0.05)
    var best = 0.0
    var i = 0
    while i + window <= s.count {
        let rms = (s[i..<i + window].reduce(0) { $0 + $1 * $1 } / Double(window)).squareRoot()
        best = max(best, rms)
        i += window / 2
    }
    return (20 * log10(max(peak, 1e-9)), 20 * log10(max(best, 1e-9)))
}

func scaled(_ s: [Float], _ g: Float) -> [Float] { s.map { $0 * g } }

var report = "name\tseconds\tpeak dBFS\tloudest 50 ms RMS dBFS\n"
@MainActor func emit(_ samples: [Float], _ name: String) throws {
    try write(samples, name)
    let l = level(samples)
    report += name + String(format: "\t%.2f\t%.1f\t%.1f\n", Double(samples.count) / sr, l.peak, l.rms)
}

// References: what painting already plays, at the volumes `SoundPlayer` gives them.
try emit(scaled(ToneSynth.kalimba(frequency: EraSynth.sunScale[4], sampleRate: sr), 0.29), "ref-paint-note-sun")
try emit(scaled(ToneSynth.celesta(frequency: EraSynth.moonScale[4], sampleRate: sr), 0.2465), "ref-paint-note-moon")
try emit(scaled(ToneSynth.twinkle(frequency: 2 * EraSynth.moonScale[4], sampleRate: sr), 0.24), "ref-glass-note")

let voices: [(EraVoice, String, Float)] = [
    (.tick(step: 0), "wheel-tick-0547", 0.44), (.tick(step: 6), "wheel-tick-1500", 0.44), (.tick(step: 11), "wheel-tick-2026", 0.44),
    (.lit(step: 5), "wheel-lit-1248", 1),
    (.passage(.tiles(.moon)), "door-tiles-moon", 1), (.passage(.tiles(.sun)), "door-tiles-sun", 1),
    (.passage(.nave), "door-nave", 1), (.passage(.wash(.moon)), "door-wash-moon", 1), (.passage(.wash(.sun)), "door-wash-sun", 1),
    (.passage(.wayBack), "door-way-back", 1), (.passage(.still(.moon)), "door-still-moon", 1),
    (.wash(.moon, index: 4), "watercolor-wash-moon", 1), (.wash(.sun, index: 4), "watercolor-wash-sun", 1),
    (.drop(variant: 0), "watercolor-drop", 1), (.bloom(index: 4, variant: 1), "watercolor-bloom", 1),
    (.dried(index: 4), "watercolor-dried", 1), (.finale(.moon), "watercolor-finale-moon", 1), (.finale(.sun), "watercolor-finale-sun", 1),
]
for (voice, name, gain) in voices { try emit(scaled(EraSynth.samples(of: voice), gain), name) }

// The reel: the wheel rolled back from the present to 1248, clicking into place, the nave's
// passage, a few washes, water and a bloom, the sheet drying, and the way home from Paint by Mosaic.
var reel = EraSynth.Mix(seconds: 24, sr: sr)
var t = 0.3
let rows = 40
for row in stride(from: rows - 1, through: 8, by: -1) {
    let step = Int((Double(row) / Double(rows - 1) * 11).rounded())
    reel.add(EraSynth.samples(of: .tick(step: step)), at: t, gain: row > 20 ? 0.24 : 0.44)
    t += row > 20 ? 0.05 : 0.07 + 0.01 * Double(20 - row)
}
reel.add(EraSynth.samples(of: .lit(step: 2)), at: t + 0.3, gain: 1)
t += 1.4
reel.add(EraSynth.samples(of: .passage(.nave)), at: t, gain: 1)
t += 4.0
let melody = [2, 3, 4, 3, 2, 1]
for (k, i) in melody.enumerated() {
    reel.add(EraSynth.samples(of: .wash(.moon, index: i)), at: t, gain: 1)
    t += 0.7 + 0.15 * Double(k % 2)
}
reel.add(EraSynth.samples(of: .drop(variant: 2)), at: t, gain: 1); t += 0.6
reel.add(EraSynth.samples(of: .bloom(index: 1, variant: 3)), at: t, gain: 1); t += 1.6
reel.add(EraSynth.samples(of: .dried(index: 1)), at: t, gain: 1); t += 1.2
reel.add(EraSynth.samples(of: .finale(.moon)), at: t, gain: 1); t += 3.4
reel.add(EraSynth.samples(of: .passage(.wayBack)), at: t, gain: 1)
try emit(reel.samples, "reel")

try report.write(to: out.appendingPathComponent("levels.tsv"), atomically: true, encoding: .utf8)
print(report)
