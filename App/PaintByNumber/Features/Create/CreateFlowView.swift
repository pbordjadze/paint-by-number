import CoreGraphics
import os
import PaintCore
import SwiftUI
import UIKit

/// New painting: pick a photo (library, camera or a sample) → tune the template → paint.
///
/// Start Painting goes into the painting in one move (`StartHandoff`, `StartHandoffPlan`): the
/// flow's controls fade around its picture, which then moves once to where the painting's page will
/// be (`PaintingLayout.page`), the making-of show playing there when it plays. The painting opens
/// beneath the cover this flow is presented in; once its canvas has drawn, the picture, by then the
/// page as the canvas draws it (`HandoffPage`), stays where it is while the flow's paper fades away
/// around it, and the canvas beneath shows the same. The cover's background is clear for that
/// (`AppShellView`), so the flow draws its own.
struct CreateFlowView: View {
    /// A bundled sample to open straight on its preview (demo scenarios).
    var openingSample: Sample?
    /// A photo dropped on the gallery: the flow opens on its preview.
    var droppedPhoto: Data?
    /// The dropped or opened file's name, when it has one.
    var droppedTitle: String?
    /// The draft to continue refining (`Drafts`): the flow opens on its preview.
    var resuming: Drafts.Opened?
    var onStart: (Artwork) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.startHandoff) private var handoff
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(Library.self) private var library
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @State private var model = CreateModel(previewStyle: Self.previewStyle)
    @State private var path: [Step] = []
    /// Where the preview's picture is on screen, which the show or the hand-off moves it from.
    @State private var previewPicture = PreviewPictureProbe()
    /// The flow's safe area as SwiftUI has laid it out, which the status bar's going changes on an
    /// iPad (`letStatusBarGo`).
    @State private var safeArea = EdgeInsets()

    // Into the painting (`handOver`).
    /// Start has saved the painting: the flow is on its way to it.
    @State private var isHandingOver = false
    @State private var handingOver: Task<Void, Never>?
    /// The flow's screens, which fade away around the picture on Start.
    @State private var controlsOpacity = 1.0
    /// The flow's paper, which stays until the painting beneath has drawn, then fades to it.
    @State private var paperOpacity = 1.0
    @State private var hidesStatusBar = false
    /// The making-of show playing over the flow (Settings › The Making-of).
    @State private var makingOf: MakingOfRequest?
    /// The preview's picture on its way to the painting, when no show plays.
    @State private var departure: PictureDeparture?
    /// The picture has made its one move.
    @State private var hasArrived = false
    /// Where the painting's page is expected (window coordinates), and the page as the canvas will
    /// draw it there, and since when the picture has shown it.
    @State private var expectedPage: CGRect?
    @State private var page: CGImage?
    @State private var pageShownAt: ContinuousClock.Instant?
    /// The painting has been pushed beneath the cover.
    @State private var isOpening = false
    /// The show is over: it ended, was skipped, or couldn't be made.
    @State private var showEnded = false
    /// How the show leaves, once the painting has drawn.
    @State private var leaving = MakingOfView.Leaving.staying
    @State private var isDissolving = false

    enum Step: Hashable { case preview }

    private struct MakingOfRequest {
        let source: MakingOfSource
        /// Where the preview's picture was (window coordinates): the show's picture starts there.
        let entry: CGRect?
    }

    var body: some View {
        flow
            .opacity(controlsOpacity)
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
            .background(Theme.paper.ignoresSafeArea().opacity(paperOpacity))
            .overlay {
                if let makingOf {
                    MakingOfView(
                        source: makingOf.source, entry: makingOf.entry, place: expectedPage, arrived: hasArrived,
                        page: page, leaving: leaving, onFinish: { showDidEnd() })
                }
            }
            .overlay {
                if let departure { DepartingPicture(departure: departure, page: page) }
            }
            // Touches go nowhere on the way to the painting, but for the show while it plays.
            .overlay {
                if isHandingOver && !(makingOf != nil && hasArrived && !showEnded) { Color.clear.contentShape(.rect) }
            }
            // The painting has no status bar: the flow lets it go before its picture moves, so the
            // place it moves to is the one the painting will have.
            .statusBarHidden(hidesStatusBar)
            .onChange(of: handoff?.phase) { finishIfReady() }
    }

    private var flow: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Step.self) { _ in
                    TemplatePreviewView(model: model, onStart: start, pictureProbe: previewPicture)
                }
        }
        .task {
            // A dropped photo or demo opens straight on the preview (pushing while the cover
            // is still being presented would stall the presentation).
            guard model.source == nil else { return }
            if let droppedPhoto {
                model.load(imageData: droppedPhoto, title: droppedTitle)
            } else if let resuming {
                model.load(draft: resuming.draft, photo: resuming.photo, kept: resuming.kept)
            } else if let openingSample {
                model.load(sample: openingSample)
            }
        }
        #if DEBUG
        .task {
            // A cancelled wait must not signal readiness.
            guard ShellDemo.current == .create || ShellDemo.current?.opensSamples == true else { return }
            do { try await Task.sleep(for: ShellDemo.pickerLoadAllowance) } catch { return }
            DemoMode.markReady()
        }
        .onChange(of: model.isFinal) { _, isFinal in
            guard isFinal else { return }
            if ShellDemo.current?.movesASlider == true, model.settingsOrigin == .suggested {
                // As a painter would: Detail moved a step off the suggestion and released.
                model.detail = model.detail < 0.75 ? model.detail + 0.25 : model.detail - 0.25
                model.settingsChanged()
                return
            }
            if ShellDemo.current?.refines == true, model.refinements.isEmpty, let template = model.preview?.template {
                // As a painter would in Refine; the preview opens it (`TemplatePreviewView`).
                model.refine(ShellDemo.refinements(for: template))
                return
            }
            // `create-tip` is ready once its tip is up (`ShellDemo.prepare`).
            // `create-refine-guide` is ready once the guide's practice canvas shows (`RefineView.land`).
            if (openingSample != nil && ShellDemo.current != .createTip && ShellDemo.current?.opensGuide == nil)
                || ShellDemo.current == .createFromFile {
                DemoMode.markReady()
            }
        }
        #endif
        // With the template on screen too: its trail, once its edits are laid, goes with the draft.
        .onChange(of: DraftKeeping(draft: model.draft, shown: model.preview?.id)) { old, keeping in
            if let draft = keeping.draft, let photo = model.source?.preview {
                library.drafts.keep(draft, photo: photo, kept: model.keptTrail)
            } else if let old = old.draft, model.source != nil, old.photoID == model.photoID {
                // Undone down to nothing. Another photo, or none, leaves the draft of the last.
                library.drafts.drop(photoID: old.photoID)
            }
        }
        .onChange(of: library.drafts.saveFailed == model.photoID) { _, failed in
            // Shown on the preview and in Refine (`DraftSaveToast`), told here once.
            if failed { Announcer.announce(DraftSaveToast.text) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            library.drafts.saveNow()
            if phase == .background {
                let drafts = library.drafts
                BackgroundSaving.shared.hold { await drafts.flush() }
            }
        }
        .onDisappear {
            model.cancelAll()
            library.drafts.saveNow()
            // A flow replaced on the way (a file opened meanwhile) opens no painting.
            handingOver?.cancel()
        }
    }

    @ViewBuilder
    private var root: some View {
        if droppedPhoto != nil || openingSample != nil || resuming != nil {
            TemplatePreviewView(model: model, onStart: start, onClose: { dismiss() }, pictureProbe: previewPicture)
        } else {
            PhotoSourceView(model: model, initialPane: initialPane, onClose: { dismiss() }) {
                path = [.preview]
            }
        }
    }

    /// Settings › Preview, or the scenario's (demo launches).
    private static var previewStyle: PreviewStyle {
        #if DEBUG
        if let style = ShellDemo.current?.previewStyle { return style }
        #endif
        return Preferences().previewStyle
    }

    /// The `create-samples` demos open on the Samples pane; everything else starts on Photos.
    private var initialPane: PhotoSourceView.Pane {
        #if DEBUG
        if ShellDemo.current?.opensSamples == true { return .samples }
        #endif
        return .photos
    }

    /// Saves the full-resolution template to the library and goes into the painting; the draft of
    /// this photo, if the painter kept one, has done its work. With Settings › The Making-of on, the
    /// saved painting's show plays on the way, and the painting takes over when it ends.
    private func start() async throws {
        let draft = try await model.makeDraft()
        let artwork = try await library.create(draft)
        library.drafts.drop(photoID: model.photoID)
        PaintTips.pageMade()
        let show = Preferences().playsMakingOf ? model.makingOfSource(for: draft, artworkID: artwork.id) : nil
        handOver(artwork, template: draft.template, show: show)
    }

    // MARK: Into the painting

    /// Start has saved `artwork`: the picture comes in over the preview's (the show's photo, or the
    /// preview's picture whole), the flow's controls fade around it, the status bar goes, and the
    /// picture moves once to where the painting's page will be, the show playing there. Then the
    /// painting opens beneath the cover (`onStart`, `StartHandoff`), where nothing will move it.
    /// Reduce Motion: the picture comes in at its place instead, once the status bar is gone.
    private func handOver(_ artwork: Artwork, template: Template, show: MakingOfSource?) {
        guard !isHandingOver else { return }
        isHandingOver = true
        let window = previewPicture.window
        let entry = StartHandoffPlan.entry(reduceMotion: reduceMotion, from: previewPicture.picture)
        if let entry {
            if let show {
                makingOf = MakingOfRequest(source: show, entry: entry)
            } else if let picture = model.preview?.picture {
                departure = PictureDeparture(picture: picture, rect: entry, radius: Theme.cardRadius, opacity: 0)
            }
        }
        handingOver = Task {
            if entry != nil {
                withAnimation(.easeOut(duration: StartHandoffPlan.lift)) { departure?.opacity = 1 }
                try? await Task.sleep(for: .seconds(StartHandoffPlan.lift))
            }
            withAnimation(.easeOut(duration: StartHandoffPlan.clear)) { controlsOpacity = 0 }
            try? await Task.sleep(for: .seconds(StartHandoffPlan.clear))
            await letStatusBarGo(in: window)
            guard !Task.isCancelled else { return }
            let place = window.flatMap { pagePlace(of: template, in: $0) }
            expectedPage = place
            if let place { renderPage(of: template, size: place.size) }
            Log.create.notice("Hand-off: the page is expected at \(String(describing: place), privacy: .public)")
            if entry != nil {
                // The show's place, a frame before it moves there: the move sets out from it.
                try? await Task.sleep(for: .milliseconds(33))
            } else {
                // Nowhere to move from: it comes in where it goes.
                if let show {
                    makingOf = MakingOfRequest(source: show, entry: nil)
                } else if let place, let picture = model.preview?.picture {
                    departure = PictureDeparture(picture: picture, rect: place, radius: 0, opacity: 0)
                    withAnimation(.easeOut(duration: StartHandoffPlan.glide)) { departure?.opacity = 1 }
                }
            }
            withAnimation(.smooth(duration: StartHandoffPlan.glide)) {
                hasArrived = true
                if entry != nil, let place {
                    departure?.rect = place
                    departure?.radius = 0
                }
            }
            try? await Task.sleep(for: .seconds(StartHandoffPlan.glide))
            guard !Task.isCancelled else { return }
            // Once the picture is still: opening a painting keeps the main thread busy a moment.
            onStart(artwork)
            isOpening = true
            finishIfReady()
        }
    }

    /// Hides the status bar and waits until the window is laid out without it, and the flow too:
    /// the page's place is worked out from that layout. UIKit says the status bar is hidden a
    /// moment before the safe area follows (on CI's iPad, every time), so where the status bar
    /// alone keeps the top clear (`statusBarSetsTheTop`) the safe area itself is waited for; where
    /// a sensor housing does, it doesn't change.
    private func letStatusBarGo(in window: UIWindow?) async {
        let before = window?.safeAreaInsets
        let wasHidden = window?.windowScene?.statusBarManager?.isStatusBarHidden ?? true
        hidesStatusBar = true
        guard let window, let before, !wasHidden else { return }
        let start = ContinuousClock.now
        let deadline = start + StartHandoffPlan.statusBarHides
        while window.windowScene?.statusBarManager?.isStatusBarHidden == false, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if Self.statusBarSetsTheTop(window) {
            while window.safeAreaInsets == before, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        let laidOut = ContinuousClock.now + StartHandoffPlan.layoutFollows
        while abs(window.safeAreaInsets.top - safeArea.top) > 0.5, ContinuousClock.now < laidOut {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let waited = ContinuousClock.now - start
        Log.create.notice(
            "Hand-off: the status bar went in \(String(describing: waited), privacy: .public), safe area top \(Double(before.top), privacy: .public) → \(Double(window.safeAreaInsets.top), privacy: .public) (the flow's \(Double(safeArea.top), privacy: .public))")
    }

    /// Whether the window's top safe area is the status bar's alone, so that it goes with it: on an
    /// iPad, or a phone with no sensor housing (none with a home indicator has one).
    private static func statusBarSetsTheTop(_ window: UIWindow) -> Bool {
        window.traitCollection.userInterfaceIdiom == .pad || window.safeAreaInsets.bottom == 0
    }

    /// Where a new painting's page of `template` will be in `window` (its coordinates), as the
    /// painting screen lays itself out there (`PaintingLayout`), from the window's own bounds and
    /// safe area as UIKit has them.
    private func pagePlace(of template: Template, in window: UIWindow) -> CGRect? {
        let insets = window.safeAreaInsets
        let rightToLeft = layoutDirection == .rightToLeft
        let size = CGSize(
            width: window.bounds.width - insets.left - insets.right,
            height: window.bounds.height - insets.top - insets.bottom)
        guard size.width > 0, size.height > 0 else { return nil }
        let inputs = PaintingLayout.Inputs(
            size: size,
            safe: EdgeInsets(
                top: insets.top, leading: rightToLeft ? insets.right : insets.left, bottom: insets.bottom,
                trailing: rightToLeft ? insets.left : insets.right),
            regularWidth: sizeClass == .regular, dynamicTypeSize: dynamicTypeSize, rows: paletteRows,
            colors: PaletteBar.visibleColorCount(template), isComplete: false)
        let page = PaintingLayout(inputs).page(
            of: CGSize(width: template.width, height: template.height), inputs: inputs, rightToLeft: rightToLeft)
        return page.isPlace ? page : nil
    }

    /// Draws the page as the canvas will (`HandoffPage`), which the picture then becomes: the
    /// preview's at once, the show's once it is over.
    private func renderPage(of template: Template, size: CGSize) {
        let look = HandoffPage.Look(
            size: size, scale: displayScale, paper: paperAppearance, interfaceIsDark: colorScheme == .dark,
            lineWeight: lineWeight, reduceMotion: reduceMotion)
        Task {
            guard let image = await HandoffPage.render(template, look: look) else {
                Log.create.error("Hand-off: the page couldn't be drawn; the picture will fade instead")
                return
            }
            page = image
            if makingOf == nil {
                withAnimation(.easeInOut(duration: StartHandoffPlan.settle)) { departure?.showsPage = true }
                pageShownAt = .now
            } else if showEnded {
                pageShownAt = .now
            }
        }
    }

    /// The show is over (ended, skipped, or couldn't be made): its picture settles into the page.
    private func showDidEnd() {
        guard !showEnded else { return }
        showEnded = true
        if page != nil { pageShownAt = .now }
        finishIfReady()
    }

    /// Hands over once the picture is in its place, the show (if one plays) is over, and the
    /// painting beneath has drawn, or has been given up on.
    private func finishIfReady() {
        guard isOpening, !isDissolving, makingOf == nil || showEnded else { return }
        switch handoff?.phase {
        case .ready(_, let reported)?: dissolve(into: reported)
        case .timedOut?: giveUp()
        default: break
        }
    }

    /// The painting beneath has drawn, its page at `reported` (window coordinates): the picture,
    /// the page as the canvas draws it by now, stays where it is while the paper fades away around
    /// it, and the canvas beneath shows the same. Should the page be elsewhere than expected, the
    /// picture moves there first (Reduce Motion: it fades out with the paper instead).
    private func dissolve(into reported: CGRect) {
        isDissolving = true
        Log.create.notice("Hand-off: the painting drew, its page at \(String(describing: reported), privacy: .public)")
        Task {
            await pageSettled()
            // Where the picture stays: on the canvas's page.
            var inPlace = false
            if let expected = expectedPage, StartHandoffPlan.matches(expected, reported) {
                // Within a point: onto the canvas's page exactly, which no one sees.
                inPlace = true
                leaving = .moving(reported)
                departure?.rect = reported
            } else if let target = StartHandoffPlan.correction(
                expected: expectedPage ?? .null, reported: reported, reduceMotion: reduceMotion) {
                Log.create.error("Hand-off: the page is not where it was expected; the picture moves there")
                withAnimation(.smooth(duration: StartHandoffPlan.correct)) {
                    leaving = .moving(target)
                    departure?.rect = target
                }
                try? await Task.sleep(for: .seconds(StartHandoffPlan.correct))
                // The page was drawn at the expected size: at another, the canvas draws it otherwise.
                inPlace = expectedPage.map { abs($0.width - target.width) <= 1 && abs($0.height - target.height) <= 1 } ?? false
            }
            let staysAsThePage = inPlace && page != nil
            let place: CGRect? = switch leaving {
            case .moving(let target): target
            case .staying, .revealing, .fading: nil
            }
            withAnimation(.easeInOut(duration: StartHandoffPlan.reveal)) {
                paperOpacity = 0
                leaving = staysAsThePage ? .revealing(place) : .fading(place)
                if !staysAsThePage { departure?.opacity = 0 }
            }
            try? await Task.sleep(for: .seconds(StartHandoffPlan.reveal + 0.05))
            handoff?.complete()
        }
    }

    /// Waits until the picture has become the page as the canvas draws it (at most a moment for
    /// the page to be drawn).
    private func pageSettled() async {
        for _ in 0..<40 where page == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let shownAt = pageShownAt else { return }
        let wait = shownAt + .seconds(StartHandoffPlan.settle) - .now
        if wait > .zero { try? await Task.sleep(for: wait) }
    }

    /// The painting didn't draw in time (a slow open, or the recovery screen): the flow fades away
    /// alone, and the painting stays pushed beneath.
    private func giveUp() {
        isDissolving = true
        Log.create.notice("Hand-off: the painting never drew; the cover fades away")
        Task {
            withAnimation(.easeInOut(duration: StartHandoffPlan.reveal)) {
                leaving = .fading(nil)
                departure?.opacity = 0
                paperOpacity = 0
            }
            try? await Task.sleep(for: .seconds(StartHandoffPlan.reveal + 0.05))
            handoff?.complete()
        }
    }
}

/// The preview's picture, between Start and the painting: fixed in its place, then moved to where
/// the painting's page will be, its corners squaring as the page's are, and becoming the page as
/// the canvas draws it (`showsPage`).
private struct PictureDeparture {
    let picture: CreateModel.Picture
    /// Window coordinates.
    var rect: CGRect
    var radius: CGFloat
    var opacity: Double
    var showsPage = false
}

private struct DepartingPicture: View {
    let departure: PictureDeparture
    let page: CGImage?

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            ZStack {
                picture
                if let page, departure.showsPage {
                    Image(decorative: page, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .transition(.opacity)
                }
            }
            .frame(width: departure.rect.width, height: departure.rect.height)
            .clipShape(.rect(cornerRadius: departure.radius, style: .continuous))
            .offset(x: departure.rect.minX - origin.x, y: departure.rect.minY - origin.y)
            .opacity(departure.opacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var picture: some View {
        switch departure.picture {
        case .painting(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        case .lineArt(let drawing):
            LineArtLayer(drawing: drawing, picture: CGRect(origin: .zero, size: departure.rect.size), scale: 1)
                .equatable()
        }
    }
}

/// What the flow hands the drafts (`Drafts.keep`): the draft, and the template on screen, whose
/// trail goes with it once the draft's edits are all laid.
private struct DraftKeeping: Equatable {
    let draft: CreateDraft?
    let shown: UUID?
}
