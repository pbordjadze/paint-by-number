import Foundation
import SwiftUI
import WidgetKit

/// A frame for the finished paintings, one each day in turn: on the Home Screen, and in StandBy
/// beside the clock, where it is the app's name made literal. It asks for nothing.
struct FrameWidget: Widget {
    static let kind = "Frame"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FrameProvider()) { entry in
            FrameWidgetView(entry: entry)
                .containerBackground(Look.paper, for: .widget)
                .widgetURL(entry.painting.map { OutsideShelf.link(toPainting: $0.id) })
        }
        .configurationDisplayName("Finished Paintings")
        .description("One of your finished paintings, a new one each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct FrameEntry: TimelineEntry {
    var date = Date.now
    var painting: OutsideShelf.Finished.Painting?
    var picture: URL?
}

struct FrameProvider: TimelineProvider {
    /// Days laid out ahead; the app reloads the widgets sooner whenever the shelf changes.
    static let days = 7

    func placeholder(in context: Context) -> FrameEntry { FrameEntry() }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FrameEntry) -> Void) {
        completion(Self.entries(from: .now, days: 1).first ?? FrameEntry())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FrameEntry>) -> Void) {
        let entries = Self.entries(from: .now, days: Self.days)
        let after = Calendar.current.date(byAdding: .day, value: Self.days, to: Calendar.current.startOfDay(for: .now)) ?? .now
        completion(Timeline(entries: entries.isEmpty ? [FrameEntry()] : entries, policy: .after(after)))
    }

    /// An entry for today from `start` and one at each of the midnights after it.
    static func entries(from start: Date, days: Int, calendar: Calendar = .current) -> [FrameEntry] {
        guard let shelf = OutsideShelf.shared(), let finished = shelf.finished() else { return [] }
        let today = calendar.startOfDay(for: start)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let number = calendar.ordinality(of: .day, in: .era, for: day) ?? offset
            let painting = finished.painting(onDay: number)
            return FrameEntry(date: offset == 0 ? start : day, painting: painting, picture: painting.map { shelf.url($0.picture) })
        }
    }
}

struct FrameWidgetView: View {
    let entry: FrameEntry

    var body: some View {
        if let painting = entry.painting {
            ShelfPicture(url: entry.picture)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel(Text(painting.title))
        } else {
            EmptyShelf(words: "Finish a painting and it hangs here.")
        }
    }
}
