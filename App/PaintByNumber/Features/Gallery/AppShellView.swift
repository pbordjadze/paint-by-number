import SwiftUI

/// The app's main navigation (gallery → painting, create flow).
struct AppShellView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Paint by Numbers", systemImage: "paintpalette", description: Text("Gallery coming soon."))
        }
    }
}
