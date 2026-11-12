import SwiftUI
import Testing
import UIKit
@testable import PaintByNumber

/// Screens let go of the flow they show once they close. Refine's Layers anchor once kept a
/// closure of Refine's view, and with it the create flow and its templates, past every trip into
/// Refine (painting-company row 263: 150 to 200 MB a trip, never freed); every functional test
/// passed, and only a measurement found it. Each test shows a screen in a window, takes it away,
/// and expects nothing but SwiftUI to have held its model.
@MainActor
struct LeakTests {
    @Test func refineLetsGoOfTheCreateFlowOnceItCloses() async throws {
        weak var flow: CreateModel?
        try await show {
            let model = CreateModel()
            flow = model
            return AnyView(RefineView(model: model)
                .environment(Library(store: ArtworkStore(root: Fixtures.temporaryDirectory())))
                .environment(UnlimitedPaintings(store: nil, defaults: nil)))
        }
        #expect(await released { flow == nil }, "Refine's screen kept the create flow after it closed")
    }

    /// Shows the view in a window of its own until it has appeared and been laid out (Refine's
    /// bar measured, its Layers hook in place), then takes the window away.
    private func show(_ make: () -> AnyView) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: make())
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(2))
        window.rootViewController = nil
        window.isHidden = true
    }

    /// Whether `gone` comes true within a few seconds, as SwiftUI lets go of the view graph.
    private func released(_ gone: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if gone() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return gone()
    }
}
