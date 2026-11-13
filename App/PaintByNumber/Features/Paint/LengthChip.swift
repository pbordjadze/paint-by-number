import Foundation
import PaintCore
import SwiftUI

/// The Painting Length chip (painting-company row 239, "Paint Now"): on a painting not begun,
/// under its bar, "~20 min · 406 areas", which opens the Painting Lengths; picking another
/// cuts the picture again in place (`Library.recut`). It is what the create flow's preview and
/// its sliders did before a picked picture opened straight as a painting, and it goes with the
/// first area painted.
struct LengthChip: View {
    let regionCount: Int
    /// The length the painting was cut for; nil when none was recorded.
    let length: PaintingLength?
    /// The re-cut under way, 0…1; nil when none is.
    let progress: Double?
    /// The areas of the other lengths' cuts the painting has had while open: their rows say
    /// what the chip would, not the band a length aims for.
    var cutAreas: [PaintingLength: Int] = [:]
    let onPick: (PaintingLength) -> Void

    var body: some View {
        Menu {
            // Each length with the time it aims for, so the choice isn't blind (the Mac's QA). A
            // toggle per row, the menu's own checkmark: a Label's title shows only its first Text
            // there, which hid the chosen length's time (painting-company row 305).
            ForEach(PaintingLength.allCases, id: \.self) { choice in
                Toggle(isOn: Binding(
                    get: { choice == length },
                    set: { _ in if choice != length { onPick(choice) } }
                )) {
                    Text(choice.name)
                    Text(Self.rowTime(of: choice, chosen: length, regionCount: regionCount, cutAreas: cutAreas))
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 44)
                    Text("Cutting again…")
                } else {
                    Image(systemName: "hourglass")
                        .accessibilityHidden(true)
                    Text(Self.summary(regionCount: regionCount))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.medium))
            // The bar's ink, never the accent: gold is for stars, sparkles and the crescent.
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(.capsule)
        }
        .disabled(progress != nil)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(Text("Painting Length"))
        .accessibilityValue(Text(progress == nil ? accessibilityValue : String(localized: "Cutting again…")))
        .accessibilityHint(Text("Cuts the picture again for a shorter or longer painting"))
        .accessibilityIdentifier("length-chip")
    }

    private var accessibilityValue: String {
        let summary = Self.summary(regionCount: regionCount)
        guard let length else { return summary }
        return String(localized: "paint.lengthChip.value", defaultValue: "\(length.name), \(summary)",
                      comment: "VoiceOver value of the painting's Painting Length chip; the arguments are the length (Quick, Relaxed, Detailed) and the summary, e.g. Relaxed, ~20 min · 406 areas")
    }

    /// A length's row's time: the cut on screen's and those made while open, as the chip says it
    /// (`PaintingTime`; the Mac's QA: "Relaxed, 20 min – 50 min" beside a chip saying ~15 min),
    /// else the times a length not cut yet can give (`expectedTimes`).
    static func rowTime(
        of choice: PaintingLength, chosen: PaintingLength?, regionCount: Int, cutAreas: [PaintingLength: Int]
    ) -> String {
        var known = cutAreas.mapValues { PaintingTime.estimate(regionCount: $0) }
        if let chosen { known[chosen] = PaintingTime.estimate(regionCount: regionCount) }
        if let seconds = known[choice] { return PaintingTimeText.approximate(seconds) }
        let times = expectedTimes(of: choice, known: known)
        let low = shown(times.lowerBound), high = shown(times.upperBound)
        return low < high ? Self.range(low, high) : PaintingTimeText.approximate(times.upperBound)
    }

    /// The times (seconds) a length not cut yet can give, by what the lengths cut so far gave
    /// (`known`): the band it aims for (`PaintingLength.timeBand`), never longer than the
    /// nearest longer length's cut nor shorter than the nearest shorter one's; and from that
    /// shorter cut's time up where it fell short of its own band, since a photo without the
    /// areas for one length hasn't them for a longer one either (the Mac's re-check of
    /// November 10: on a five-area photo Quick offered "8 min – 25 min" and came out ~5 min,
    /// Detailed "40 min – 2 hr" beside Relaxed's ~5 min). An empty range is the longer cut's time.
    static func expectedTimes(of choice: PaintingLength, known: [PaintingLength: Double]) -> ClosedRange<Double> {
        let order = PaintingLength.allCases
        guard let place = order.firstIndex(of: choice) else { return choice.timeBand }
        var low = choice.timeBand.lowerBound, high = choice.timeBand.upperBound
        if let shorter = order[..<place].last(where: { known[$0] != nil }), let seconds = known[shorter] {
            low = seconds < shorter.timeBand.lowerBound ? seconds : max(low, seconds)
        }
        if let longer = order[(place + 1)...].first(where: { known[$0] != nil }), let seconds = known[longer] {
            high = min(high, seconds)
        }
        return min(low, high)...high
    }

    /// `seconds` as the menu shows a time: whole five minutes up to 55 (5 the least), then half
    /// hours, as `PaintingTimeText.approximate` rounds.
    private static func shown(_ seconds: Double) -> Double {
        let minutes = seconds / 60
        return minutes < 55 ? Double(max(5, Int((minutes / 5).rounded()) * 5)) * 60 : (minutes / 30).rounded() * 30 * 60
    }

    /// "20 min – 50 min": the times a length aims for (`PaintingLength.timeBand`).
    static func band(of length: PaintingLength) -> String {
        range(length.timeBand.lowerBound, length.timeBand.upperBound)
    }

    private static func range(_ low: Double, _ high: Double) -> String {
        let style = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .abbreviated)
        let low = Duration.seconds(low).formatted(style)
        let high = Duration.seconds(high).formatted(style)
        return String(localized: "paint.lengthChip.band", defaultValue: "\(low) – \(high)",
                      comment: "Under a Painting Length in the painting's length chip menu: the times it aims for; the arguments are durations, e.g. 20 min – 50 min")
    }

    /// "~20 min · 406 areas".
    static func summary(regionCount: Int) -> String {
        let time = PaintingTimeText.approximate(PaintingTime.estimate(regionCount: regionCount))
        let areas = TemplateCounts.areas(regionCount)
        return String(localized: "paint.lengthChip", defaultValue: "\(time) · \(areas)",
                      comment: "The painting's Painting Length chip, on a painting not begun; the arguments are the estimated time and the areas, e.g. ~20 min · 406 areas")
    }
}
