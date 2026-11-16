import AppIntents
import Foundation
import SwiftUI
import WidgetKit

/// The painting in progress. Its button paints the next area: the widget shows the picture the
/// app drew of the painting with that area painted, and the app paints it for real when it next
/// opens (`OutsideShelf`). Nothing counts taps, days or streaks.
struct PaintingWidget: Widget {
    static let kind = "Painting"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PaintingProvider()) { entry in
            PaintingWidgetView(entry: entry)
                .containerBackground(Look.paper, for: .widget)
                .widgetURL(entry.now.map { OutsideShelf.link(toPainting: $0.artwork) })
        }
        .configurationDisplayName("Painting in Progress")
        .description("Your painting as it stands. Paint One Area fills in the next area, right here.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Paints the next area of the painting in progress: counts the tap on the shelf, and the
/// widget, drawn again, shows the next picture.
struct PaintOneArea: AppIntent {
    static let title: LocalizedStringResource = "Paint One Area"
    static var description: IntentDescription? { IntentDescription("Paints the next area of your painting in progress.") }
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        OutsideShelf.shared()?.addTap()
        return .result()
    }
}

struct PaintingEntry: TimelineEntry {
    var date = Date.now
    var now: OutsideShelf.Now?
    var taps = 0
    var picture: URL?

    var step: OutsideShelf.Now.Step? { now?.step(after: taps) }
    var offersTap: Bool { now?.offersTap(after: taps) ?? false }
    var fraction: Double {
        guard let now, now.total > 0, let step else { return 0 }
        return min(1, Double(step.painted) / Double(now.total))
    }
    /// One area from finished: the app keeps that one, and its finish, for itself.
    var isAtTheLast: Bool {
        guard let now, let step else { return false }
        return step.painted == now.total - 1
    }

    static func current() -> PaintingEntry {
        guard let shelf = OutsideShelf.shared(), let now = shelf.now() else { return PaintingEntry() }
        let taps = shelf.taps(for: now)
        return PaintingEntry(now: now, taps: taps, picture: now.step(after: taps).map { shelf.url($0.picture) })
    }
}

struct PaintingProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaintingEntry { PaintingEntry() }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (PaintingEntry) -> Void) {
        completion(.current())
    }

    /// One entry that stays: the app reloads the widgets when it lays the shelf out, and the
    /// system after each Paint One Area.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PaintingEntry>) -> Void) {
        completion(Timeline(entries: [.current()], policy: .never))
    }
}

struct PaintingWidgetView: View {
    let entry: PaintingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    private var percent: String { entry.fraction.formatted(.percent.precision(.fractionLength(0))) }

    // MARK: Home Screen

    @ViewBuilder private var small: some View {
        if entry.now != nil {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if entry.offersTap, let next = entry.step?.next {
                        Button(intent: PaintOneArea()) { Swatch(paint: next, diameter: 40) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(paintLabel(next))
                            .padding(2)
                    }
                }
        } else {
            empty
        }
    }

    @ViewBuilder private var medium: some View {
        if let now = entry.now {
            HStack(spacing: 14) {
                picture
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    words(now)
                    Spacer(minLength: 4)
                    action
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            empty
        }
    }

    @ViewBuilder private var large: some View {
        if let now = entry.now {
            VStack(spacing: 12) {
                picture
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) { words(now) }
                    Spacer(minLength: 8)
                    action
                }
            }
        } else {
            empty
        }
    }

    private var picture: some View {
        ShelfPicture(url: entry.picture)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    @ViewBuilder private func words(_ now: OutsideShelf.Now) -> some View {
        Text(now.title)
            .font(Look.title(.headline))
            .lineLimit(2)
        Text("\(percent) painted")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The button while the shelf has a picture for the next area; past them, a plain line
    /// that says the painting goes on in the app, which a tap anywhere opens.
    @ViewBuilder private var action: some View {
        if entry.offersTap, let next = entry.step?.next {
            Button(intent: PaintOneArea()) {
                HStack(spacing: 7) {
                    Swatch(paint: next, diameter: 22)
                    Text("Paint One Area")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.leading, 5)
                .padding(.trailing, 11)
                .padding(.vertical, 5)
                .foregroundStyle(.white)
                .background(Look.signature, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paintLabel(next))
        } else {
            Text(entry.isAtTheLast ? "Open to paint the last area" : "Open to keep painting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Look.signature)
                .widgetAccentable()
        }
    }

    private var empty: some View { EmptyShelf(words: "Start a painting and it waits for you here.") }

    private func paintLabel(_ paint: OutsideShelf.Now.Paint) -> Text {
        if let name = paint.name {
            Text("Paint one area, \(paint.number), \(name)")
        } else {
            Text("Paint one area, paint \(paint.number)")
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: entry.fraction) {
            Image(systemName: "paintbrush.pointed.fill")
        } currentValueLabel: {
            Text(percent)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel(entry.now.map { Text($0.title) } ?? Text("Paint by Moonlight"))
        .accessibilityValue(Text("\(percent) painted"))
    }

    @ViewBuilder private var rectangular: some View {
        if let now = entry.now {
            VStack(alignment: .leading, spacing: 1) {
                Text(now.title)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                Text("\(percent) painted")
                if let next = entry.step?.next {
                    if let name = next.name {
                        Text("Next: \(next.number) · \(name)")
                    } else {
                        Text("Next: paint \(next.number)")
                    }
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Start a painting and it waits for you here.")
                .font(.caption)
        }
    }

    @ViewBuilder private var inline: some View {
        if let now = entry.now {
            Text(verbatim: "\(now.title) · \(percent)")
        } else {
            Text("Paint by Moonlight")
        }
    }
}

/// A paint as the app's palette shows it: its color with its number on it, in New York.
struct Swatch: View {
    let paint: OutsideShelf.Now.Paint
    let diameter: CGFloat

    private var color: Color {
        Color(red: Double(paint.red) / 255, green: Double(paint.green) / 255, blue: Double(paint.blue) / 255)
    }
    /// Dark numerals on a light paint, light on a dark one.
    private var isLight: Bool {
        0.2126 * Double(paint.red) + 0.7152 * Double(paint.green) + 0.0722 * Double(paint.blue) > 150
    }

    var body: some View {
        Text(verbatim: "\(paint.number)")
            .font(.system(size: diameter * 0.46, weight: .semibold, design: .serif))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(isLight ? Color.black.opacity(0.75) : Color.white)
            .frame(width: diameter, height: diameter)
            .background(color, in: .circle)
            .overlay { Circle().strokeBorder(.white, lineWidth: diameter * 0.07) }
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
    }
}
