import SwiftUI

/// The clock behind the secret door: a year on four wheels, which Paint by Moonlight's Settings ›
/// About shows at the present year once the Version row is held, and the era's own Settings at 547.
/// Rolled to a year and left there, it hands that year over (`onSettle`); what a year opens is the
/// caller's to say. No label and no hint: whoever finds it works out what it does.
public struct EraClock: View {
    private let onSettle: (Int) -> Void
    @State private var digits: [Int]
    @State private var settling: Task<Void, Never>?

    /// How long the wheels must rest on a year before it counts: a wheel spun past 547 isn't a
    /// visit to it.
    static let rest: Duration = .milliseconds(700)

    public init(year: Int, onSettle: @escaping (Int) -> Void) {
        self.onSettle = onSettle
        _digits = State(initialValue: Self.digits(of: year))
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { place in
                Picker(selection: $digits[place]) {
                    ForEach(0..<10, id: \.self) { digit in
                        Text(digit, format: .number.grouping(.never))
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .monospacedDigit()
                            .tag(digit)
                    }
                } label: {
                    Text(Self.placeName(place))
                }
                .pickerStyle(.wheel)
                .frame(width: 44, height: 132)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(localized: "eraClock.label", defaultValue: "Year", bundle: .ravenna,
                                        comment: "VoiceOver name of the clock behind the secret door: four wheels, one digit each, which together show a year")))
        .accessibilityValue(Text(Self.year(of: digits), format: .number.grouping(.never)))
        .onChange(of: digits) { _, digits in
            settling?.cancel()
            settling = Task {
                try? await Task.sleep(for: Self.rest)
                guard !Task.isCancelled else { return }
                onSettle(Self.year(of: digits))
            }
        }
        .onDisappear { settling?.cancel() }
    }

    static func digits(of year: Int) -> [Int] {
        let year = min(max(year, 0), 9999)
        return [year / 1000, year / 100 % 10, year / 10 % 10, year % 10]
    }

    static func year(of digits: [Int]) -> Int {
        digits.reduce(0) { $0 * 10 + $1 }
    }

    private static func placeName(_ place: Int) -> String {
        switch place {
        case 0: String(localized: "eraClock.thousands", defaultValue: "Thousands", bundle: .ravenna,
                       comment: "VoiceOver name of the clock's first wheel (the year's thousands)")
        case 1: String(localized: "eraClock.hundreds", defaultValue: "Hundreds", bundle: .ravenna,
                       comment: "VoiceOver name of the clock's second wheel (the year's hundreds)")
        case 2: String(localized: "eraClock.tens", defaultValue: "Tens", bundle: .ravenna,
                       comment: "VoiceOver name of the clock's third wheel (the year's tens)")
        default: String(localized: "eraClock.ones", defaultValue: "Ones", bundle: .ravenna,
                        comment: "VoiceOver name of the clock's fourth wheel (the year's ones)")
        }
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
