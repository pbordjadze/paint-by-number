import SwiftUI

/// The year setter behind the secret door: one wheel of years, under a plain Year row in Paint by
/// Moonlight's Settings › About (at the present year) and in the era's own Settings (at 0547).
/// Rolled to a year and left there, it hands that year over (`onSettle`); what a year opens is the
/// caller's to say. The wheel reads like any year setting, with a long reach: 0547 first, then
/// each century, then the last years one by one up to the present (`years`), so the far end is
/// a flick away. It answers as it turns: the further back the year, the warmer its numerals,
/// toward the gold of a smalto, and the heavier each step back is in the hand.
public struct EraClock: View {
    private let onSettle: (Int) -> Void
    @State private var year: Int
    @State private var settling: Task<Void, Never>?
    /// The wheel and the rails' gap grow with the numerals' text size.
    @ScaledMetric(relativeTo: .title2) private var wheelWidth: CGFloat = 120
    @ScaledMetric(relativeTo: .title2) private var wheelHeight: CGFloat = 112
    @ScaledMetric(relativeTo: .title2) private var railGap: CGFloat = 36

    /// How long the wheel must rest on a year before it counts: a wheel spun past 0547 isn't a
    /// visit to it.
    static let rest: Duration = .milliseconds(700)

    public init(year: Int, onSettle: @escaping (Int) -> Void) {
        self.onSettle = onSettle
        _year = State(initialValue: Self.nearest(to: year))
    }

    public var body: some View {
        Picker(selection: $year) {
            ForEach(Self.years, id: \.self) { year in
                Text(verbatim: Self.text(of: year))
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.mix(with: Self.gold, by: Self.age(of: year)))
                    .tag(year)
            }
        } label: {
            Text(String(localized: "eraClock.label", defaultValue: "Year", bundle: .ravenna,
                        comment: "VoiceOver name of the year setter behind the secret door: one wheel of years"))
        }
        .pickerStyle(.wheel)
        .frame(width: wheelWidth, height: wheelHeight)
        .clipped()
        .overlay { rails }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(trigger: year) { old, new in
            new < old ? .impact(weight: .heavy, intensity: 0.25 + 0.75 * Self.age(of: new)) : nil
        }
        .onChange(of: year) { _, year in
            settling?.cancel()
            settling = Task {
                try? await Task.sleep(for: Self.rest)
                guard !Task.isCancelled else { return }
                onSettle(year)
            }
        }
        .onDisappear { settling?.cancel() }
    }

    /// Two hairlines across the wheel, above and below the year read, in the numerals' warmth.
    private var rails: some View {
        let ink = Color.primary.mix(with: Self.gold, by: Self.age(of: year)).opacity(0.45)
        return VStack(spacing: railGap) {
            Rectangle().fill(ink).frame(height: 1)
            Rectangle().fill(ink).frame(height: 1)
        }
        .frame(width: wheelWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Smalti gold, as Ravenna's theme has it.
    static let gold = Color(red: 0.788, green: 0.635, blue: 0.290)

    /// The wheel's years, oldest first: 0547, the centuries from 600 to 2000, 2010, and every
    /// year from 2020 to the present.
    public static var years: [Int] {
        [EraYear.byzantium] + Array(stride(from: 600, through: 2000, by: 100)) + [2010]
            + Array(2020...max(2020, EraYear.present))
    }

    /// The wheel's year closest to `year` (the later on a tie), for a year the wheel lacks.
    public static func nearest(to year: Int) -> Int {
        years.min { abs($0 - year) < abs($1 - year) || (abs($0 - year) == abs($1 - year) && $0 > $1) } ?? year
    }

    /// A year as the setter writes it: four digits, so the far end reads 0547.
    public static func text(of year: Int) -> String {
        String(format: "%04d", min(max(year, 0), 9999))
    }

    /// How far back a year is, from 0 at the present (and after) to 1 at 0547 and before it.
    static func age(of year: Int) -> Double {
        let present = EraYear.present
        guard year < present else { return 0 }
        return min(1, Double(present - year) / Double(present - EraYear.byzantium))
    }
}

/// Which era a year on the clock opens: 547, the year San Vitale in Ravenna was consecrated, is
/// Byzantium; the present (or any later year) is Paint by Moonlight's own. Every other year opens
/// nothing.
public enum EraYear {
    public static let byzantium = 547

    /// The present year by the device's calendar.
    public static var present: Int { Calendar.current.component(.year, from: .now) }

    public static func opensByzantium(_ year: Int) -> Bool { year == byzantium }

    public static func returnsToThePresent(_ year: Int) -> Bool { year >= present }
}
