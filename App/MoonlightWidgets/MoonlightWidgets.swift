import SwiftUI
import UIKit
import WidgetKit

/// Paint by Moonlight's widgets (painting-company row 348): the painting in progress, which its
/// Paint One Area button paints an area of, and a frame for the finished ones. They draw what
/// the app laid out for them (`OutsideShelf`) and never read a painting themselves.
@main
struct MoonlightWidgets: WidgetBundle {
    var body: some Widget {
        PaintingWidget()
        FrameWidget()
    }
}

/// The app's colors, as its asset catalog and `Theme` have them.
enum Look {
    static let paper = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.078, green: 0.067, blue: 0.090, alpha: 1)
            : UIColor(red: 0.949, green: 0.945, blue: 0.957, alpha: 1)
    })
    static let signature = Color(red: 0.482, green: 0.247, blue: 0.494)
    static let gold = Color(red: 0.788, green: 0.635, blue: 0.290)
    /// Titles in New York, as the app's.
    static func title(_ style: Font.TextStyle) -> Font { .system(style, design: .serif).weight(.semibold) }
}

/// A picture from the shelf, nil when its file is gone.
struct ShelfPicture: View {
    let url: URL?
    var fills = false

    var body: some View {
        if let url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .aspectRatio(contentMode: fills ? .fill : .fit)
                .accessibilityHidden(true)
        }
    }
}

/// What a widget says when it has nothing to show yet: the crescent and one line.
struct EmptyShelf: View {
    let words: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(Look.gold)
                .widgetAccentable()
            Text(words)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
