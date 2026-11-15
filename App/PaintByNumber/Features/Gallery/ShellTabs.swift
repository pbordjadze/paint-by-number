#if UNRELEASED
import Foundation
import SwiftUI

/// The shell's tabs in SideStore and Debug builds (painting-company row 328): the gallery, the
/// Paint page as a place of its own, and the system's search tab. The release has the gallery
/// alone, the Paint page under its + (`AppShellView`).
nonisolated enum ShellTab: String, CaseIterable, Sendable {
    case gallery, paint, search

    /// The tab a launch opens on: the gallery, or with nothing in it the Paint page, where a
    /// first painting begins. Within a launch a scene keeps the tab it was on (scene storage).
    static func atLaunch(isBare: Bool) -> ShellTab { isBare ? .paint : .gallery }

    /// The tab to be on with `openPainting` open, or none: a painting is the gallery's, whichever
    /// tab it was picked or made on, so closing it lands among the paintings and leaves the
    /// Paint tab as it was.
    func holding(openPainting: UUID?) -> ShellTab { openPainting == nil ? self : .gallery }

    /// This launch, for a scene to tell the tab it stored in an earlier one.
    static let launch = UUID().uuidString
}

/// The system's tab bar over the shell's three places: at the bottom of an iPhone, at the top of
/// an iPad, the search tab apart as the system keeps it. Each place brings its own navigation
/// stack. A painting hides the bar from its own screen (`AppShellView`), and what covers the shell
/// (the create flow, the arch, the sheets) is laid over this view, so over the bar too.
struct ShellTabs<Gallery: View, Paint: View, Search: View>: View {
    @Binding var selection: ShellTab
    @ViewBuilder let gallery: () -> Gallery
    @ViewBuilder let paint: () -> Paint
    @ViewBuilder let search: () -> Search

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: ShellTab.gallery) {
                gallery()
            } label: {
                Label("Gallery", systemImage: "square.grid.2x2")
            }
            Tab(value: ShellTab.paint) {
                paint()
            } label: {
                Label("Paint", systemImage: "paintbrush.pointed")
            }
            Tab(value: ShellTab.search, role: .search) {
                search()
            }
        }
    }
}

/// The Paint page as a tab: the page under the bar's large title, the gear above as on the
/// gallery, and no ×. It stays as the painter left it (its scroll position) while they are on
/// another tab or in a painting. What is picked opens in the create flow, over the bar (`onChoose`).
struct PaintTab: View {
    /// A painting is on its way in under a cover: no bar comes back beneath it.
    var hidesTabBar: Bool
    var onSettings: () -> Void
    var onChoose: (PaintChoice) -> Void

    var body: some View {
        NavigationStack {
            PhotoSourceView(onChoose: onChoose)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape", action: onSettings)
                    }
                }
                .toolbarVisibility(hidesTabBar ? .hidden : .automatic, for: .tabBar)
        }
        #if DEBUG
        .task {
            // The Paint page's scenarios: its tiles load their pictures (a cancelled wait must
            // not signal readiness).
            guard ShellDemo.current?.opensPaintPage == true else { return }
            do { try await Task.sleep(for: ShellDemo.pickerLoadAllowance) } catch { return }
            DemoMode.markReady()
        }
        #endif
    }
}
#endif
