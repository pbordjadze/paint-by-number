import Observation
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
/// them is drawn on to it (`pull`), where it clicks into place, so the eras are found without
/// being shown. Its Year row shows the year it rests on (`reporting(to:)`, `Value`), as a system
/// date row shows what its wheel is turned to.
public struct EraClock: View {
    private let onSettle: (Int) -> Void
    private var reading: Reading?
    /// The wheel's rows, made once, not at each turn (the wheel's body runs again at every year
    /// it rests on, and a row's ink reads the calendar).
    private let rows: [Row]
    @State private var year: Int
    @State private var settling: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.eraClockSound) private var sound

    /// How long the wheel must rest on a year before it counts: a wheel spun past 0547 isn't a
    /// visit to it.
    static let rest: Duration = .milliseconds(700)
    /// How long a wheel rests beside an era's year before it is drawn on to it.
    static let pull: Duration = .milliseconds(320)
    /// The rest with VoiceOver, which steps the wheel a year a swipe and says each: long enough
    /// to hear a year and swipe on past it. Nothing is pulled then, or a lit year beside the one
    /// spoken would take the wheel from under the next swipe.
    static let spokenRest: Duration = .seconds(2)

    public init(year: Int, onSettle: @escaping (Int) -> Void) {
        self.onSettle = onSettle
        rows = Self.rows()
        _year = State(initialValue: Self.nearest(to: year))
    }

    /// One year of the wheel as it is drawn.
    private struct Row: Identifiable {
        let year: Int
        let text: String
        let isLit: Bool
        let ink: Color
        /// Its ink while it is the year read: a quiet year at full strength, as a system wheel
        /// draws the row under its band.
        let readInk: Color
        var id: Int { year }
    }

    private static func rows() -> [Row] {
        let present = EraYear.present
        return years.map { year in
            Row(year: year, text: text(of: year), isLit: isLit(year), ink: ink(of: year, present: present),
                readInk: ink(of: year, present: present, read: true))
        }
    }

    public var body: some View {
        Picker(selection: $year) {
            ForEach(rows) { row in
                Text(verbatim: row.text)
                    .font(.system(.title2, design: .serif, weight: row.isLit ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(row.year == year ? row.readInk : row.ink)
                    .tag(row.year)
            }
        } label: {
            Text(String(localized: "eraClock.label", defaultValue: "Year", bundle: .ravenna,
                        comment: "VoiceOver name of the year setter behind the secret door: one wheel of years"))
        }
        .pickerStyle(.wheel)
        .modifier(WheelFrame())
        .frame(maxWidth: .infinity)
        // As the painting screen's bars do: past xxLarge a year's numerals outgrow the wheel's
        // rows, and the wheel would outgrow a phone's screen.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .sensoryFeedback(trigger: year) { old, new in
            // An era's year clicks into place, from either side; a step back otherwise weighs
            // what its age does. A step forward has the wheel's own tick alone.
            if Self.isLit(new) { return .impact(flexibility: .rigid, intensity: 1) }
            return new < old ? .impact(weight: .heavy, intensity: 0.25 + 0.75 * Self.age(of: new)) : nil
        }
        .onChange(of: year) { _, year in
            if let sound, let row = rows.firstIndex(where: { $0.year == year }) {
                sound.turned(row, rows.count, rows[row].isLit)
            }
            settling?.cancel()
            settling = Task {
                if !voiceOver, let era = Self.pulled(from: year) {
                    try? await Task.sleep(for: Self.pull)
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) { self.year = era }
                    return
                }
                try? await Task.sleep(for: voiceOver ? Self.spokenRest : Self.rest)
                guard !Task.isCancelled else { return }
                // A rest that lands while the row is closing the wheel leaves the row its own year.
                if let reading, reading.isOpen { reading.year = year }
                onSettle(year)
            }
        }
        .onDisappear { settling?.cancel() }
    }

    /// What the wheel sounds as it turns (SideStore and Debug builds; painting-company row 381):
    /// Paint by Moonlight's to give, at its root (`EraSounds`), and each Settings' Sounds switch's
    /// to take away. Nil, the wheel is silent, as the release's is.
    public struct Sound {
        /// The wheel came to `row` of `rows` (0 the oldest year), lit when it opens an era.
        public let turned: (_ row: Int, _ rows: Int, _ lit: Bool) -> Void

        public init(turned: @escaping (_ row: Int, _ rows: Int, _ lit: Bool) -> Void) {
            self.turned = turned
        }
    }

    /// The wheel, telling `reading` each year it comes to rest on.
    public func reporting(to reading: Reading) -> EraClock {
        var clock = self
        clock.reading = reading
        return clock
    }

    /// The year a wheel last came to rest on, for its Year row; nil before it has (or once the
    /// row has closed it), when the row shows its own year. Settings holds it and only the row's
    /// `Value` reads it, so a turn of the wheel redraws that one text, not the list.
    @Observable
    public final class Reading {
        public var year: Int?
        /// False once the row has closed the wheel: a rest still settling then changes nothing.
        @ObservationIgnored public var isOpen = true

        public init() {}
    }

    /// The Year row's value: the year the wheel rests on, or `home`, written as the wheel writes
    /// it, its digits of one width so the row holds still as they change.
    public struct Value: View {
        private let reading: Reading
        private let home: Int

        public init(_ reading: Reading, home: Int) {
            self.reading = reading
            self.home = home
        }

        public var body: some View {
            Text(verbatim: EraClock.text(of: reading.year ?? home))
                .monospacedDigit()
        }
    }

    /// The wheel's size, growing with the numerals' text size up to the clock's cap (read here,
    /// inside the cap, and not on the clock, which sees the painter's own size). Tall enough for
    /// two years above and below the one read, fading as a system wheel does.
    private struct WheelFrame: ViewModifier {
        @ScaledMetric(relativeTo: .title2) private var width: CGFloat = 120
        @ScaledMetric(relativeTo: .title2) private var height: CGFloat = 176

        func body(content: Content) -> some View {
            content.frame(width: width, height: height).clipped()
        }
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
    /// SideStore and Debug builds every other year quieter, so the lit ones stand out, but for
    /// the year `read`, under the band, which is never quieter than its neighbours.
    static func ink(of year: Int, present: Int = EraYear.present, read: Bool = false) -> Color {
        if isLit(year) { return gold }
        let warm = Color.primary.mix(with: gold, by: age(of: year, present: present))
        #if UNRELEASED
        return read ? warm : warm.opacity(0.6)
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
    static func age(of year: Int, present: Int = EraYear.present) -> Double {
        guard year < present else { return 0 }
        return min(1, Double(present - year) / Double(present - EraYear.byzantium))
    }
}

/// Which era a year on the clock opens: 547, the year San Vitale in Ravenna was consecrated, is
/// Byzantium; 1248 Stained Glass and 1765 Woodblock, in SideStore and Debug builds; the present (or any later year)
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

    /// 1765, the year of Harunobu's first prints in full colour from many blocks, registered on
    /// kentō: Woodblock's (SideStore and Debug builds; painting-company row 375).
    public static let woodblock = 1765
    /// 1502, the year of Dürer's *Young Hare*, the most famous early watercolor: Watercolor's
    /// (SideStore and Debug builds; painting-company row 373).
    public static let watercolor = 1502

    /// 1000, a round year for the modes still to come: The Frame's (SideStore and Debug builds;
    /// painting-company row 379), a mode that is only the frame every mode shares.
    public static let frame = 1000

    /// The years that open an era, oldest first: the ones the wheel lights.
    public static var modes: [Int] {
        #if UNRELEASED
        return [byzantium, frame, stainedGlass, watercolor, woodblock]
        #else
        return [byzantium]
        #endif
    }

    public static func opensStainedGlass(_ year: Int) -> Bool { year == stainedGlass && modes.contains(year) }

    public static func opensWoodblock(_ year: Int) -> Bool { year == woodblock && modes.contains(year) }
    public static func opensWatercolor(_ year: Int) -> Bool { year == watercolor && modes.contains(year) }

    public static func opensTheFrame(_ year: Int) -> Bool { year == frame && modes.contains(year) }

    public static func returnsToThePresent(_ year: Int) -> Bool { year >= present }

    /// Whether a wheel left on `year` takes the painter somewhere: an era's year, or the present.
    public static func opensAnEra(_ year: Int) -> Bool { returnsToThePresent(year) || modes.contains(year) }
}

extension EnvironmentValues {
    /// The year wheel's sound (`EraClock.Sound`), nil for none.
    @Entry public var eraClockSound: EraClock.Sound? = nil
}
