#if DEBUG
import Foundation

/// `-clipSpins "547,1502,1248,2026"` (Debug builds; painting-company's `tools/clip`): each time a
/// year wheel (`EraClock`) comes out, it spins by itself to the next of these years, a row a
/// step, easing out as a flicked wheel does, then rests there as if a thumb had left it. With
/// `-passageFrameClock N` each step is held N 60ths, as the doors' passages are, so a recording
/// slowed N times keeps every step of the spin. A wheel spun by hand can't be recorded so: the
/// simulator keeps almost none of its frames.
@MainActor
enum ClipSpin {
    private static let targets: [Int] = (UserDefaults.standard.string(forKey: "clipSpins") ?? "")
        .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    private static var next = 0
    /// While a spin turns the wheel, which then neither draws on to an era nor settles.
    static private(set) var isSpinning = false
    /// Whether the wheel that just came out was spun (it settles where the spin ended).
    static private(set) var didSpin = false
    /// 60ths of a second each step is held: the doors' frame clock, or 1.
    private static var hold: Int { max(1, UserDefaults.standard.integer(forKey: "passageFrameClock")) }
    /// The spin's length in 60ths (at the frame clock's speed, so 1.4 s once sped back up).
    static let steps = 84

    static func spin(from year: Int, rows: [Int], set: (Int) -> Void) async {
        didSpin = false
        guard next < targets.count, let from = rows.firstIndex(of: year) else { return }
        let target = targets[next]
        next += 1
        guard let to = rows.firstIndex(of: target) ?? rows.indices.min(by: { abs(rows[$0] - target) < abs(rows[$1] - target) })
        else { return }
        let tick = Duration.microseconds(1_000_000 * hold / 60)
        // A beat before the thumb comes down, as a viewer sees the wheel first.
        try? await Task.sleep(for: tick * 20)
        if Task.isCancelled { return }
        isSpinning = true
        defer { isSpinning = false; didSpin = !Task.isCancelled }
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = 1 - pow(1 - t, 3)
            set(rows[from + Int((Double(to - from) * eased).rounded())])
            try? await Task.sleep(for: tick)
            if Task.isCancelled { return }
        }
    }
}
#endif
