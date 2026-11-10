import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI
import UIKit

/// Opens an artwork for painting: loads it off the main actor, hosts `PaintView`, and
/// saves progress while the user paints. When it can't be opened it explains why and offers
/// recovery (`PaintingRecoveryView`).
struct ArtworkPaintingView: View {
    let artworkID: UUID
    var onClose: () -> Void

    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    /// The hand-off from Start Painting: this painting, just made, opens under the create flow's
    /// cover, which dissolves into it once the canvas has drawn (`StartHandoff`).
    @Environment(\.startHandoff) private var handoff
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @Environment(\.colorScheme) private var colorScheme
    @State private var autosaver: PaintingAutosaver?
    /// Made once when the painting is presented, not in `body`: each autosave replaces the
    /// artwork in the library, and values made afresh would reach `PaintView` as changed
    /// environment on every one. None of what they read changes while painting.
    @State private var sourcePhotoLoader: SourcePhotoLoader?
    @State private var feedbackSource: FeedbackSource?
    /// The push has finished. Only then does the painting replace its thumbnail: the zoom
    /// transition lays the screen out afresh every frame, and the painting screen rendered at
    /// each of them kept CI's simulator from answering for up to half a minute (hundreds of
    /// renders in one push), where the thumbnail costs next to nothing.
    @State private var hasLanded = false
    @State private var failure: Library.OpenError?
    @State private var regeneration: Task<Void, Never>?
    @State private var regenerationFailed = false
    /// The painting's paints may come out different made again (`Library.regenerationMayRepaint`).
    @State private var regenerationMayRepaint = false
    @State private var notice: ShownNotice?
    /// The painting's length chip's re-cut, under way (`recut(to:)`).
    @State private var recutting: Task<Void, Never>?
    /// ✎ Change opening or saving (`openChange`, `changeEnded`): never cancelled when the screen
    /// goes, so Done's change is saved whatever comes after.
    @State private var changing: Task<Void, Never>?
    @State private var recutFailed = false
    /// The cuts this painting has had while open, by length, the one it opened with too: going
    /// back to one puts that very template back (`Library.restoreCut`), never makes it again (the
    /// Mac's QA: Relaxed again came back as another painting, 347 areas then 344, made again from
    /// `source.jpg` where the first came from the photo itself). ✎ Change's Done forgets them.
    @State private var cuts: [PaintingLength: Cut] = [:]

    private struct Cut {
        let template: Template
        let settings: GenerationSettings
    }
    /// What the failure toast says: the re-cut's, or ✎ Change's.
    @State private var recutFailedText = ""
    /// ✎ Change's drawing tools, open over the painting (`PaintingChangeView`), with the
    /// refinements they opened on.
    @State private var change: PaintingChange?
    /// The change the cover was opened for, read once it has gone: the cover's item is already
    /// nil when its `onDismiss` runs (the Mac's QA, November 9: Done kept nothing).
    @State private var presentedChange: PaintingChange?
    /// ✎ Change was tapped before Unlimited Paintings, which the drawing tools come with, was bought.
    @State private var offersChangeUnlock = false
    @Environment(UnlimitedPaintings.self) private var paintings
    /// Where a half-open iPhone Duo's fold lies across the screen (`FoldPlace`): the toasts keep to
    /// the painting's page beside it.
    @State private var foldPlace: FoldPlace?
    @Environment(\.layoutDirection) private var layoutDirection
    /// Half open like a book, how far the painting's page ends from the trailing edge; else 0.
    private var beyondTheFold: CGFloat {
        guard let foldPlace, let fold = foldPlace.active(rightToLeft: layoutDirection == .rightToLeft), fold.isUpright
        else { return 0 }
        return max(0, foldPlace.size.width - fold.frame.minX)
    }

    private struct ShownNotice: Equatable {
        var notice: OpenNotice
        var id = UUID()
    }

    private var artwork: Artwork? { library.artwork(with: artworkID) }

    /// Name Your Painting (Rename Painting once it has a name), from the Finished bar's name: the
    /// field starts empty, the name it has as its placeholder, and Save with nothing typed keeps
    /// that name as the painting's own.
    @State private var isNaming = false
    @State private var nameText = ""
    @State private var namingTitle = ""
    @State private var namingUnnamed = false

    private func startNaming() {
        nameText = ""
        namingTitle = artwork?.title ?? ""
        namingUnnamed = artwork?.isNamed == false
        isNaming = true
    }

    private func saveName() {
        let typed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        library.rename(artworkID, to: typed.isEmpty ? namingTitle : typed)
    }
    private var saveFailed: Bool { library.writeFailures[artworkID] != nil }

    /// Under the create flow's cover, waiting to be handed the screen (past the hand-off's time too,
    /// while the making-of plays on): nothing of the painting fades in, since the cover is what
    /// dissolves.
    private var isUnderCover: Bool { handoff?.isAwaiting(artworkID) == true }

    /// What the canvas tells once its first frame is on screen, while the cover waits for it, and
    /// when a layout moves the template after that.
    private var canvasReport: ((CGRect) -> Void)? {
        guard isUnderCover else { return nil }
        return { rect in canvasDrew(rect) }
    }

    /// The canvas has its template at `templateRect` (the window's coordinates): where the cover's
    /// picture is to be.
    private func canvasDrew(_ templateRect: CGRect) {
        Log.create.notice("Painting reports its template at \(String(describing: templateRect), privacy: .public)")
        handoff?.paintingDrew(artworkID, templateRect: templateRect)
    }

    /// Where the painting came from, for feedback given on it. The painter's own photo is read
    /// (as stored, off the main actor) only if they choose to send it; a library picture's is
    /// in the repository.
    private func makeFeedbackSource(for artwork: Artwork) -> FeedbackSource {
        let store = library.store, id = artworkID
        var photo: (@Sendable () async -> Data?)?
        if artwork.sampleName == nil {
            photo = { await Background.run { try? Data(contentsOf: store.url(.source, of: id)) } }
        }
        return FeedbackSource(
            artworkID: id, settings: artwork.settings, settingsOrigin: artwork.settingsOrigin,
            paintingLength: artwork.paintingLength, sampleName: artwork.sampleName, createdAt: artwork.createdAt, photo: photo)
    }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let autosaver, hasLanded {
                PaintView(
                    session: autosaver.session, title: artwork?.title ?? "", onClose: close,
                    onName: { startNaming() }, isNamed: artwork?.isNamed ?? true,
                    onTemplateFrame: canvasReport, onFirstFrame: heldScreen == nil ? nil : { releaseHeldScreen() },
                    onChange: changeAction)
                    .environment(\.sourcePhotoLoader, sourcePhotoLoader)
                    .environment(\.feedbackSource, feedbackSource)
                    .background { RevisionObserver(session: autosaver.session, onChange: autosaver.sessionChanged) }
                    // A new template (a re-cut) is a new session: the screen starts afresh on it.
                    .id(ObjectIdentifier(autosaver.session))
                    // Nothing is painted while the picture is cut again: it would be lost.
                    .overlay {
                        if recutting != nil || changing != nil { Color.clear.contentShape(.rect) }
                    }
                    .transition(.opacity)
            } else if let failure {
                PaintingRecoveryView(
                    artwork: artwork, failure: failure,
                    progress: regeneration == nil ? nil : (library.regenerating[artworkID] ?? 0),
                    didFail: regenerationFailed, mayRepaint: regenerationMayRepaint,
                    onRegenerate: regenerate, onDelete: delete, onClose: onClose)
                    .transition(.opacity)
                    .task(id: failure) {
                        guard failure == .damaged(canRegenerate: true) else { return }
                        regenerationMayRepaint = await library.regenerationMayRepaint(artworkID)
                    }
                    #if DEBUG
                    .onAppear {
                        if ShellDemo.current == .galleryDamaged { DemoMode.markReady() }
                    }
                    #endif
            } else if let artwork {
                // What the zoom transition shows, and where it lands while the template loads.
                ArtworkThumbnail(artwork: artwork, contentMode: .fit)
                    .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                    .padding(20)
                    .overlay {
                        if autosaver == nil { ProgressView().controlSize(.large) }
                    }
            }
        }
        // Below PaintView's top bar (6 pt inset + 44 pt buttons).
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let chip = lengthChip {
                    chip.transition(.opacity)
                }
                if recutFailed {
                    Toast(text: recutFailedText, systemImage: "exclamationmark.triangle", edge: .top)
                        .allowsHitTesting(false)
                }
                if let notice {
                    Toast(text: notice.notice.text, systemImage: notice.notice.systemImage, edge: .top)
                        // Taps reach the canvas under it.
                        .allowsHitTesting(false)
                }
                if saveFailed {
                    Toast(text: String(localized: "Couldn’t save progress"), systemImage: "exclamationmark.triangle", edge: .top) {
                        Button("Retry") { library.retrySaving(artworkID) }
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding(.top, 62)
            .padding(.horizontal, 20)
            // Half open like a book, on the painting's page: the controls' page beyond the fold
            // (`PaintingLayout`) has its bar wherever its palette leaves it.
            .padding(.trailing, beyondTheFold)
            // Over the painting, like its bars.
            .environment(\.colorScheme, PaintView.chromeScheme(paper: paperAppearance, system: colorScheme))
        }
        .readsTheFold { foldPlace = $0 }
        .animation(.snappy, value: notice)
        .animation(.snappy, value: showsLengthChip)
        .animation(.snappy, value: recutFailed)
        .animation(.snappy, value: saveFailed)
        .onChange(of: saveFailed) { _, failed in
            if failed { Announcer.announce(String(localized: "Couldn’t save progress")) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $change, onDismiss: changeEnded) { change in
            PaintingChangeView(model: change.model) { refinements in
                // What Done is compared with: the refinements as the tools opened, after the
                // load's own pin or rebase, not as read from disk (the fresh reader's review).
                presentedChange?.opened = refinements
            }
        }
        .modifier(RefineUnlockOffer(isPresented: $offersChangeUnlock) { openChange() })
        .background { CanvasGesturesOverZoomDismissal(onAppear: land).frame(width: 0, height: 0) }
        .alert(namingUnnamed ? Text("Name Your Painting") : Text("Rename Painting"), isPresented: $isNaming) {
            TextField("Title", text: $nameText, prompt: Text(namingTitle))
                .submitLabel(.done)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: saveName)
        } message: {
            Text("This name shows when you share or print the painting.")
        }
        .task { await open() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            FeedbackEngine.shared.rest()
            autosaver?.saveNow(refreshThumbnail: true)
            if phase == .background {
                let library = library
                BackgroundSaving.shared.hold { await library.flush() }
            }
        }
        .onDisappear {
            regeneration?.cancel()
            recutting?.cancel()
            releaseHeldScreen()
            autosaver?.saveNow(refreshThumbnail: true)
        }
    }

    private func open() async {
        guard autosaver == nil, failure == nil else { return }
        do {
            let document = try await library.loadForPainting(artworkID)
            _ = await RenderContext.ready()
            await present(document)
        } catch {
            Log.library.error("Opening \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            withAnimation(.easeOut(duration: 0.25)) {
                failure = error as? Library.OpenError ?? .damaged(canRegenerate: false)
            }
        }
    }

    /// Callers await `RenderContext.ready()` first: the canvas this shows needs it.
    /// `replacing`: the painting on screen is made over in place (✎ Change's Done, a length's
    /// re-cut, a regeneration): the paint in hand stays in hand, the same paint or the nearest
    /// one left (`keptColor`), where a new session opened on its first color or largest area and
    /// the strip went back to its start (the Mac's QA, November 10); and the old screen stays
    /// over the new until its canvas has drawn (`holdOldScreen`), where the page went to bare
    /// paper for a frame.
    private func present(_ document: PaintingDocument, replacing: Bool = false) async {
        let previous = replacing ? autosaver?.session : nil
        let inHand = previous.flatMap { old in old.selectedColor.map { old.template.palette[$0].oklab } }
        let session: PaintingSession
        do {
            session = try await PaintingSession.make(
                template: document.template, progress: document.progress, nicknameSeed: artwork?.nicknameSeed ?? ColorNickname.seed(for: artworkID),
                nicknameVersion: artwork?.nicknameVersion ?? 1)
        } catch is CancellationError {
            return
        } catch {
            // The library hands out matching progress; this guards against a bug, not a file.
            Log.library.error("Opening \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            failure = .damaged(canRegenerate: artwork.map { ArtworkFactory.canRegenerate($0, store: library.store) } ?? false)
            return
        }
        if let inHand,
           let kept = Self.keptColor(
               inHand, palette: session.template.palette.map(\.oklab),
               open: (0..<session.paletteCount).map { !session.isColorComplete($0) }) {
            session.select(color: kept)
        }
        if previous != nil { holdOldScreen() }
        // Before the painting screen appears: its first tip and the first painting's limit.
        PaintTips.artworkOpened(artworkID)
        withAnimation(isUnderCover || previous != nil ? nil : .easeOut(duration: 0.25)) {
            failure = nil
            regenerationFailed = false
            autosaver = PaintingAutosaver(session: session, artworkID: artworkID, library: library)
            // No Photo button for a painting with no photo (one sent without it): it showed
            // enabled and did nothing (QA, November 6).
            sourcePhotoLoader = document.hasPhoto ? SourcePhotoLoader { [library, artworkID] maxPixelSize in
                await library.sourcePhoto(for: artworkID, maxPixelSize: maxPixelSize)
            } : nil
            feedbackSource = artwork.map(makeFeedbackSource)
        }
        if let notice = document.notice { show(notice) }
        Log.library.notice("Opened \(artworkID.uuidString, privacy: .public): \(document.template.regions.count, privacy: .public) regions")
        #if DEBUG
        markDemoReady()
        #endif
    }

    /// The paint nearest `oklab` among the `open` ones of `palette` (the same paint where it is
    /// still there and open), or nil when none is open.
    nonisolated static func keptColor(_ oklab: SIMD3<Float>, palette: [SIMD3<Float>], open: [Bool]) -> Int? {
        palette.indices.filter { open.indices.contains($0) && open[$0] }
            .min { ColorScience.distance(palette[$0], oklab) < ColorScience.distance(palette[$1], oklab) }
    }

    /// The old screen's picture, over the painting made over beneath it (`holdOldScreen`).
    @State private var heldScreen: UIView?

    /// Lays a picture of the window as it is over it, taking the touches meant for a screen not yet
    /// drawn, until the painting made over beneath it has drawn its first frame (`PaintView`'s
    /// `onFirstFrame`), or 4 s at most.
    private func holdOldScreen() {
        releaseHeldScreen()
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard let window, let picture = window.snapshotView(afterScreenUpdates: false) else { return }
        picture.isUserInteractionEnabled = true
        window.addSubview(picture)
        heldScreen = picture
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if heldScreen === picture { releaseHeldScreen() }
        }
    }

    private func releaseHeldScreen() {
        guard let picture = heldScreen else { return }
        heldScreen = nil
        UIView.animate(withDuration: 0.2, animations: { picture.alpha = 0 }, completion: { _ in picture.removeFromSuperview() })
    }

    /// The push finished: the painting, when loaded, takes the thumbnail's place.
    private func land() {
        guard !hasLanded else { return }
        withAnimation(isUnderCover ? nil : .easeOut(duration: 0.25)) { hasLanded = true }
        #if DEBUG
        markDemoReady()
        #endif
    }

    #if DEBUG
    /// `gallery-open` and `gallery-received` are ready once the painting is on screen.
    private func markDemoReady() {
        guard autosaver != nil, hasLanded, ShellDemo.current == .galleryOpen || ShellDemo.current == .galleryOpenNew
            || ShellDemo.current == .galleryReceived else { return }
        DemoMode.markReady()
    }
    #endif

    private func show(_ openNotice: OpenNotice) {
        let shown = ShownNotice(notice: openNotice)
        notice = shown
        Announcer.announce(openNotice.text)
        Task {
            try? await Task.sleep(for: .seconds(4))
            if notice == shown { notice = nil }
        }
    }

    private func regenerate() {
        guard let artwork, regeneration == nil else { return }
        regenerationFailed = false
        regeneration = Task {
            do {
                let document = try await library.regenerate(artwork: artworkID, settings: artwork.settings)
                _ = await RenderContext.ready()
                await present(document, replacing: true)
            } catch is CancellationError {
            } catch let error as Library.OpenError {
                failure = error
            } catch {
                Log.library.error("Regenerating \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                regenerationFailed = true
            }
            regeneration = nil
        }
    }

    /// ✎ Change in the painting's bar: in SideStore and Debug builds while the drawing tools are,
    /// for a painting with a photo to draw over (a library picture's file will do).
    private var changeAction: (() -> Void)? {
        guard let artwork, sourcePhotoLoader != nil || artwork.sampleName != nil else { return nil }
        return {
            if paintings.locksRefine { offersChangeUnlock = true } else { openChange() }
        }
    }

    /// The drawing tools on this painting as it stands (`PaintingChangeView`).
    private func openChange() {
        guard change == nil, changing == nil, recutting == nil, regeneration == nil, let autosaver, let artwork else { return }
        autosaver.saveNow()
        let template = autosaver.session.template, id = artworkID
        changing = Task {
            defer { changing = nil }
            do {
                let inputs = try await library.changeInputs(for: id)
                try Task.checkCancellation()
                let model = CreateModel(previewStyle: .painting)
                model.load(artwork: artwork, photo: inputs.photo, template: template, refinements: inputs.refinements)
                let opened = PaintingChange(model: model)
                presentedChange = opened
                change = opened
            } catch is CancellationError {
            } catch {
                Log.library.error("Opening ✎ Change on \(id.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                showChangeFailed()
            }
        }
    }

    /// The drawing tools closed: with Done and something changed, the painting takes the new
    /// template, its painted areas kept (`Library.adopt`).
    private func changeEnded() {
        guard let ended = presentedChange else { return }
        presentedChange = nil
        change = nil
        let model = ended.model
        // Closed before the tools opened (Cancel while Preparing) is a cancel too.
        guard let opened = ended.opened, !model.refiningCancelled, model.refinements != opened else {
            model.cancelAll()
            return
        }
        changing = Task {
            defer { changing = nil }
            do {
                let draft = try await model.makeDraft()
                let document = try await library.adopt(draft, into: artworkID)
                // The cuts kept were of the painting before the change.
                cuts = [:]
                _ = await RenderContext.ready()
                await present(document, replacing: true)
            } catch is CancellationError {
            } catch {
                Log.library.error("Keeping ✎ Change on \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                showChangeFailed()
            }
            model.cancelAll()
        }
    }

    private func showChangeFailed() {
        let text = String(localized: "Couldn’t change the painting")
        Announcer.announce(text)
        recutFailedText = text
        recutFailed = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            recutFailed = false
        }
    }

    /// The Painting Length chip shows on a painting not begun that was cut for a length (a
    /// picture picked, not a drawing, a page drawn or a painting someone sent), and while a
    /// re-cut is under way.
    private var showsLengthChip: Bool {
        guard let autosaver, hasLanded, let artwork else { return false }
        if recutting != nil { return true }
        return !autosaver.session.isStarted && artwork.paintingLength != nil && artwork.settings.drawing == nil
            && artwork.receivedDigest == nil
    }

    private var lengthChip: LengthChip? {
        guard showsLengthChip, let autosaver, let artwork else { return nil }
        return LengthChip(
            regionCount: autosaver.session.template.regions.count,
            length: artwork.paintingLength.flatMap(PaintingLength.init(rawValue:)),
            progress: recutting == nil ? nil : (library.regenerating[artworkID] ?? 0),
            cutAreas: cuts.mapValues { $0.template.regions.count },
            onPick: recut(to:))
    }

    /// Cuts the painting again at `length` (`Library.recut`) and opens the new cut in place.
    private func recut(to length: PaintingLength) {
        guard recutting == nil, changing == nil, regeneration == nil, let autosaver,
              length.rawValue != artwork?.paintingLength else { return }
        autosaver.saveNow()
        recutFailed = false
        if let artwork, let current = artwork.paintingLength.flatMap(PaintingLength.init(rawValue:)), cuts[current] == nil {
            cuts[current] = Cut(template: autosaver.session.template, settings: artwork.settings)
        }
        let kept = cuts[length]
        recutting = Task {
            do {
                let document = if let kept {
                    try await library.restoreCut(artwork: artworkID, length: length, template: kept.template, settings: kept.settings)
                } else {
                    try await library.recut(artwork: artworkID, length: length)
                }
                if let made = library.artwork(with: artworkID)?.settings {
                    cuts[length] = Cut(template: document.template, settings: made)
                }
                _ = await RenderContext.ready()
                await present(document, replacing: true)
                Announcer.announce(LengthChip.summary(regionCount: document.template.regions.count))
            } catch is CancellationError {
            } catch {
                Log.library.error("Re-cutting \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                recutFailedText = String(localized: "Couldn’t cut the picture again")
                recutFailed = true
                Announcer.announce(recutFailedText)
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    recutFailed = false
                }
            }
            recutting = nil
        }
    }

    private func delete() {
        library.delete(artworkID)
        onClose()
    }

    private func close() {
        autosaver?.saveNow(refreshThumbnail: true)
        onClose()
    }
}

/// The zoom transition lets a swipe down or a pinch anywhere dismiss the pushed screen, which
/// steals the canvas's pan and pinch and drops the painter back in the gallery. SwiftUI has no
/// switch for it, so this turns the recognizers behind those two gestures off on the pushed
/// controller's view once it has appeared; the edge swipe back and the Back button keep
/// working. The recognizers are found by their UIKit class names (`PaintingNavigationTests`
/// notices if they change). It also tells `onAppear` that the push has finished (SwiftUI's own
/// `onAppear` comes as it starts).
private struct CanvasGesturesOverZoomDismissal: UIViewControllerRepresentable {
    var onAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onAppear = onAppear
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) { controller.onAppear = onAppear }

    final class Controller: UIViewController {
        var onAppear: () -> Void = {}

        private static let dismissalRecognizers: Set<String> = [
            "_UIContentSwipeDismissGestureRecognizer", "_UISwipeDownGestureRecognizer", "_UITransformGestureRecognizer",
        ]

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The transition may install its recognizers just after the push completes.
            disableDismissalGestures()
            // Next turn: SwiftUI may be mid-update when UIKit calls this.
            Task { onAppear() }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                disableDismissalGestures()
            }
        }

        private func disableDismissalGestures() {
            var pushed: UIViewController? = self
            while let controller = pushed, !(controller.parent is UINavigationController) { pushed = controller.parent }
            guard let recognizers = pushed?.view.gestureRecognizers, !recognizers.isEmpty else { return }
            var names: [String] = []
            for recognizer in recognizers {
                let name = String(describing: type(of: recognizer))
                if recognizer.isEnabled && Self.dismissalRecognizers.contains(name) {
                    recognizer.isEnabled = false
                    names.append("\(name) (disabled)")
                } else {
                    names.append(name)
                }
            }
            Log.library.notice("Painting screen recognizers: \(names.joined(separator: ", "), privacy: .public)")
        }
    }
}

/// Re-evaluates only itself on each paint, keeping `PaintView` out of the invalidation.
private struct RevisionObserver: View {
    let session: PaintingSession
    var onChange: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.revision) { onChange() }
    }
}

private extension OpenNotice {
    var text: String {
        switch self {
        case .progressReset:
            String(localized: "gallery.notice.progressReset",
                   defaultValue: "This painting’s saved progress couldn’t be read, so it starts fresh.",
                   comment: "Toast when a painting's saved progress was unreadable and has been reset")
        case .regenerated(keptProgress: true):
            String(localized: "gallery.notice.regeneratedKept",
                   defaultValue: "Painting regenerated. Your painted areas were kept.",
                   comment: "Toast after a damaged painting was regenerated and its painted areas carried over")
        case .regenerated(keptProgress: false):
            String(localized: "gallery.notice.regenerated",
                   defaultValue: "Painting regenerated from the original photo.",
                   comment: "Toast after a damaged painting was regenerated from its photo without its painted areas")
        }
    }

    var systemImage: String {
        switch self {
        case .progressReset: "exclamationmark.triangle"
        case .regenerated: "checkmark.circle"
        }
    }
}

/// ✎ Change's drawing tools open on a painting: their model, and the refinements they opened
/// on, once they have (nil while Preparing).
private struct PaintingChange: Identifiable {
    let id = UUID()
    let model: CreateModel
    var opened: TemplateRefinements?
}
