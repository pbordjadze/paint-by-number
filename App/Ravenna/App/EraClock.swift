import SwiftUI

/// The year setter behind the secret door: one wheel of years, under a plain Year row in Paint by
/// Moonlight's Settings › About (at the present year) and in the era's own Settings (at 0547).
/// Rolled to a year and left there, it hands that year over (`onSettle`); what a year opens is the
/// caller's to say. The wheel reads like any year setting, with a long reach: 0547 first, then
/// each century, then the last years one by one up to the present (`years`), so the far end is
/// a flick away. It answers as it turns: the further back the year, the warmer its numerals,
/// toward the gold of a smalto, and the heavier each step back is in the hand. In SideStore and
/// Debug builds (painting-company row 366) it reaches back to 0001, the years that open an era
/// (`EraYear.modes`) lit in gold among quieter ones, and a wheel left on a year beside one of
/// them is drawn on to it (`pull`), so the eras are found without being shown.
public struct EraClock: View {
    private let onSettle: (Int) -> Void
    @State private var year: Int
    @State private var settling: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The wheel and the rails' gap grow with the numerals' text size.
    /// Tall enough for two years above and below the one read, fading as a system wheel does.
    @ScaledMetric(relativeTo: .title2) private var wheelWidth: CGFloat = 120
    @ScaledMetric(relativeTo: .title2) private var wheelHeight: CGFloat = 176
    @ScaledMetric(relativeTo: .title2) private var railGap: CGFloat = 36

    /// How long the wheel must rest on a year before it counts: a wheel spun past 0547 isn't a
    /// visit to it.
    static let rest: Duration = .milliseconds(700)
    /// How long a wheel rests beside an era's year before it is drawn on to it.
    static let pull: Duration = .milliseconds(320)

    public init(year: Int, onSettle: @escaping (Int) -> Void) {
        self.onSettle = onSettle
        _year = State(initialValue: Self.nearest(to: year))
    }

    public var body: some View {
        Picker(selection: $year) {
            ForEach(Self.years, id: \.self) { year in
                Text(verbatim: Self.text(of: year))
                    .font(.system(.title2, design: .serif, weight: Self.isLit(year) ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Self.ink(of: year))
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
                if let era = Self.pulled(from: year) {
                    try? await Task.sleep(for: Self.pull)
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { self.year = era }
                    return
                }
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

    /// The wheel's years, oldest first: 0547, the centuries from 600 to 1900, the decades from
    /// 2000, and the present's last seven years one by one (in 2026: 2000, 2010, 2020…2026), so
    /// the wheel stays short however many years pass.
    public static var years: [Int] {
        #if UNRELEASED
        return longReach
        #else
        return nearReach
        #endif
    }

    /// The release's wheel: 0547 to the present.
    static var nearReach: [Int] {
        let present = EraYear.present
        let recent = present - 6
        let centuries = stride(from: 600, through: 1900, by: 100).filter { $0 < recent }
        let decades = stride(from: 2000, to: recent, by: 10)
        let years = Set([EraYear.byzantium] + centuries + decades + Array(recent...present))
        return years.filter { $0 >= EraYear.byzantium && $0 <= max(present, EraYear.byzantium) }.sorted()
    }

    /// The wheel reaching back to 0001 (SideStore and Debug builds): the centuries to 1700, the
    /// decades from 1800, the present's last seven years one by one, and every era's year.
    static var longReach: [Int] {
        let present = EraYear.present
        let recent = present - 6
        let centuries = stride(from: 100, through: 1700, by: 100)
        let decades = stride(from: 1800, to: recent, by: 10)
        let years = Set([1] + centuries + decades + Array(recent...present) + EraYear.modes)
        return years.filter { $0 >= 1 && $0 <= max(present, 1) }.sorted()
    }

    /// Whether the wheel lights `year`: an era's (SideStore and Debug builds; the release's
    /// wheel lights none).
    public static func isLit(_ year: Int) -> Bool {
        #if UNRELEASED
        return EraYear.modes.contains(year)
        #else
        return false
        #endif
    }

    /// The numerals' color: warmer the further back; an era's year in full gold, and in
    /// SideStore and Debug builds every other year quieter, so the lit ones stand out.
    static func ink(of year: Int) -> Color {
        if isLit(year) { return gold }
        let warm = Color.primary.mix(with: gold, by: age(of: year))
        #if UNRELEASED
        return warm.opacity(0.6)
        #else
        return warm
        #endif
    }

    /// The era's year a wheel resting on `year` is drawn on to: the lit year beside it on the
    /// wheel, nil on one or between none. The present is never drawn away from.
    public static func pulled(from year: Int) -> Int? {
        let years = Self.years
        guard !isLit(year), year < EraYear.present - 6, let i = years.firstIndex(of: year) else { return nil }
        let beside = [i - 1, i + 1].filter { years.indices.contains($0) }.map { years[$0] }.filter(isLit)
        return beside.min { abs($0 - year) < abs($1 - year) }
    }

    /// The wheel's year closest to `year` (the later on a tie), for a year the wheel lacks.
    public static func nearest(to year: Int) -> Int {
        years.min { abs($0 - year) < abs($1 - year) || (abs($0 - year) == abs($1 - year) && $0 > $1) } ?? year
    }

    /// A year as the setter writes it: four digits, so the far end reads 0547.
    public static func text(of year: Int) -> String {
        String(format: "%04ld", min(max(year, 0), 9999))
    }

    /// How far back a year is, from 0 at the present (and after) to 1 at 0547 and before it.
    /// (The long reach's older years are as warm as 0547's.)
    static func age(of year: Int) -> Double {
        let present = EraYear.present
        guard year < present else { return 0 }
        return min(1, Double(present - year) / Double(present - EraYear.byzantium))
    }
}

/// Which era a year on the clock opens: 547, the year San Vitale in Ravenna was consecrated, is
/// Byzantium; 1248 Stained Glass, in SideStore and Debug builds; the present (or any later year)
/// is Paint by Moonlight's own. Every other year opens nothing.
public enum EraYear {
    public static let byzantium = 547

    /// The present year, by the Gregorian calendar whatever the device's (547 is a Gregorian
    /// year; the Japanese calendar's present would be a single digit).
    public static var present: Int { Calendar(identifier: .gregorian).component(.year, from: .now) }

    public static func opensByzantium(_ year: Int) -> Bool { year == byzantium }

    /// 1248, the year the Sainte-Chapelle in Paris was consecrated: Stained Glass's (SideStore
    /// and Debug builds; painting-company row 366).
    public static let stainedGlass = 1248

    /// 1502, the year of Dürer's *Young Hare*, the most famous early watercolor: Watercolor's
    /// (SideStore and Debug builds; painting-company row 373).
    public static let watercolor = 1502

    /// The years that open an era, oldest first: the ones the wheel lights.
    public static var modes: [Int] {
        #if UNRELEASED
        return [byzantium, stainedGlass, watercolor]
        #else
        return [byzantium]
        #endif
    }

    public static func opensStainedGlass(_ year: Int) -> Bool { year == stainedGlass && modes.contains(year) }

    public static func opensWatercolor(_ year: Int) -> Bool { year == watercolor && modes.contains(year) }

    public static func returnsToThePresent(_ year: Int) -> Bool { year >= present }

    /// Whether a wheel left on `year` takes the painter somewhere: an era's year, or the present.
    public static func opensAnEra(_ year: Int) -> Bool { returnsToThePresent(year) || modes.contains(year) }
}
