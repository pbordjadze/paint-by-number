import PaintCore
import SwiftUI
import UIKit

/// Builds the painting screen once, out of sight, while the create flow's preview is final and
/// still, so that the first Start Painting of a launch doesn't pay for SwiftUI and UIKit meeting the
/// screen's views for the first time.
///
/// On the iPad Air 5 the painting screen's first build was the worst of Start Painting's hitches
/// (126 ms of about 300 late): the type metadata of its generic views made on first use, the
/// attribute graph and UIKit's hosting views met for the first time, layout. Much of that is made
/// once a launch, so the screen is built on the preview's template in a window of its own, beneath
/// the app's and transparent, drawn once and thrown away; the real one finds it made. A hosting
/// controller in no window lays the views out but makes none of UIKit's (nor the canvas), so the
/// window is needed. In it the screen does nothing a painting does on appearing
/// (`EnvironmentValues.paintScreenIsWarmup`): no tips, no feedback engine, no hand-off report, and
/// its canvas takes no first responder and tells VoiceOver nothing (`CanvasView.isOutOfSight`).
@MainActor
enum PaintScreenWarmup {
    /// Once a launch: what it makes stays made.
    private static var isDone = false
    /// Counts the warm-ups asked for and let go: one let go (`letGo`) doesn't build.
    private static var generation = 0
    /// The window the screen is built in, while it is.
    private static var scratch: UIWindow?

    /// How long the preview is to have been final and still first: a painter who moves a slider at
    /// once makes it again, and the build would hitch under their finger.
    static let quiet = Duration.milliseconds(600)
    /// How long the screen stays built: the canvas draws a frame, then the window goes.
    static let shown = Duration.milliseconds(150)

    /// Builds the painting screen for `template` out of sight, unless it has been built this launch,
    /// is let go meanwhile, or `stillWanted` (asked after the quiet moment and again once the
    /// session is made) says no.
    static func warm(_ template: Template, stillWanted: @escaping @MainActor () -> Bool) {
        guard !isDone else { return }
        generation += 1
        let asked = generation
        Task { @MainActor in
            try? await Task.sleep(for: quiet)
            guard !isDone, asked == generation, stillWanted() else { return }
            let session = await PaintingSession.make(template: template)
            _ = await RenderContext.ready()
            // The scene in front, never one in the background, where the GPU may not be used.
            guard !isDone, asked == generation, stillWanted(),
                  UIApplication.shared.applicationState == .active,
                  let scene = UIApplication.shared.connectedScenes
                      .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  let window = scene.keyWindow
            else { return }
            isDone = true
            #if DEBUG
            TourLog.trace("mark", "warm begin")
            #endif
            scratch = build(session, in: scene, like: window)
            #if DEBUG
            TourLog.trace("mark", "warm built")
            #endif
            try? await Task.sleep(for: shown)
            letGo()
        }
    }

    /// The preview goes, or Start Painting was tapped: a warm-up still waiting won't build, and the
    /// screen built goes now, so the real one is never built beside it.
    static func letGo() {
        generation += 1
        guard let window = scratch else { return }
        scratch = nil
        window.isHidden = true
        window.rootViewController = nil
        #if DEBUG
        TourLog.trace("mark", "warm end")
        #endif
    }

    /// A window beneath `window`, transparent and taking no touches, with the painting screen in it,
    /// laid out and its views made.
    private static func build(_ session: PaintingSession, in scene: UIWindowScene, like window: UIWindow) -> UIWindow {
        // As the painting is opened under the cover: `onTemplateFrame` makes the canvas watch for
        // its first frame (`PaintCanvas.watchesFirstFrame`).
        let screen = PaintView(session: session, onTemplateFrame: { _ in })
            .environment(\.paintScreenIsWarmup, true)
        let scratch = UIWindow(windowScene: scene)
        scratch.frame = window.bounds
        scratch.windowLevel = UIWindow.Level(rawValue: window.windowLevel.rawValue - 1)
        scratch.alpha = 0
        scratch.isUserInteractionEnabled = false
        scratch.accessibilityElementsHidden = true
        scratch.rootViewController = UIHostingController(rootView: screen)
        scratch.isHidden = false
        scratch.layoutIfNeeded()
        return scratch
    }
}

extension EnvironmentValues {
    /// The painting screen is being built out of sight (`PaintScreenWarmup`): nothing it does on
    /// appearing or going is done.
    @Entry var paintScreenIsWarmup = false
}
