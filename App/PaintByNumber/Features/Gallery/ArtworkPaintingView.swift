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
    @AppStorage(SettingsKey.paletteRows) private var paletteRows = PaletteRows.default
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var autosaver: PaintingAutosaver?
    /// Made once when the painting is presented, not in `body`: each autosave replaces the
    /// artwork in the library, and values made afresh would reach `PaintView` as changed
    /// environment on every one. None of what they read changes while painting.
    @State private var sourcePhotoLoader: SourcePhotoLoader?
    /// The painting was drawn on a blank start (`PaintingDocument.startsBlank`).
    @State private var startsBlank = false
    @State private var feedbackSource: FeedbackSource?
    /// The push has finished. Only then does the painting replace its thumbnail: the zoom
    /// transition lays the screen out afresh every frame, and the painting screen rendered at
    /// each of them kept CI's simulator from answering for up to half a minute (hundreds of
    /// renders in one push), where the thumbnail costs next to nothing. Under the create flow's
    /// cover nothing of the push is seen, so the painting is built at once rather than after it
    /// (`isBuilt`): it waited 0.8 s for a zoom no one sees (painting-company row 361).
    @State private var hasLanded = false
    /// The painting was opened under the cover: built then, it stays built once the hand-off is
    /// over (no longer awaiting) though the push may not have landed yet.
    @State private var builtUnderCover = false
    /// The safe area is as the painting has it, the status bar gone (or never in the way):
    /// `waitingPage` sees it, or `land` stops waiting for it (`statusBarWait`).
    @State private var statusBarGone = false
    /// The status bar as the waiting page first found it (`StatusBarAtOpen`), read once.
    @State private var barAtOpen: StatusBarAtOpen?
    @State private var barMeasured = false
    /// Back was tapped: the status bar is back before the pop starts (`close`).
    @State private var leaving = false
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
    /// The other lengths' cuts made ahead join them (`precuts`).
    @State private var cuts: [PaintingLength: Cut] = [:]
    /// The other lengths cut ahead while the chip shows and the painter has yet to begin
    /// (`LengthPrecuts`, painting-company row 361), each into `cuts` as it is made.
    @State private var precuts = LengthPrecuts()

    private struct Cut {
        let template: Template
        let settings: GenerationSettings
    }
    /// Fine-Tune's sheet is up, from the length chip (`FineTuneSheet`).
    @State private var fineTuning = false
    /// What the failure toast says: the re-cut's, or ✎ Change's.
    @State private var recutFailedText = ""
    /// ✎ Change's drawing tools, open over the painting (`PaintingChangeView`), with the
    /// refinements they opened on.
    @State private var change: PaintingChange?
    /// The change the cover was opened for, read once it has gone: the cover's item is already
    /// nil when its `onDismiss` runs (the Mac's QA, November 9: Done kept nothing).
    @State private var presentedChange: PaintingChange?
    /// ✎ Change's edits waiting to be written (`keepChange`).
    @State private var changeKeeping: Task<Void, Never>?
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

    /// More › Show Lines on the finished painting: the painting keeps the choice, and its
    /// gallery picture follows it (`Library.setHidesLines`).
    private func linesHidden(_ hidden: Bool) {
        guard let session = autosaver?.session else { return }
        let library = library, id = artworkID, template = session.template, progress = session.progress
        Task { await library.setHidesLines(id, hidden, template: template, progress: progress) }
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

    /// The painting screen takes the thumbnail's place: once the push has landed and the status
    /// bar has gone (built before the safe area followed, the canvas's first frames put the page
    /// lower on an iPad, and it moved up), or at once under the cover (`hasLanded`).
    private var isBuilt: Bool { (hasLanded && statusBarGone) || builtUnderCover }

    /// What the zoom transition shows, and where it lands while the painting loads: the thumbnail
    /// just where the canvas will open the page, laid out by `PaintView`'s own recipe
    /// (`PaintingLayout.screen`) in the safe area the painting will have once its status bar has
    /// gone (`StatusBarAtOpen`). Centered on the whole screen, it jumped up and grew as the
    /// painting took its place (painting-company row 364). The status bar stays while it shows:
    /// hidden as the zoom began, an iPad's gallery behind it would move up under the card.
    @ViewBuilder
    private func waitingPage(_ artwork: Artwork) -> some View {
        if let opening = waitingTemplate(artwork) {
            GeometryReader { geo in
                let raw = geo.safeAreaInsets
                // Read before the first frame too, so the thumbnail starts where it stays.
                let bar = barMeasured ? barAtOpen : Self.statusBarAtOpen(raw)
                let frame = Self.waitingFrame(
                    of: opening, readerSize: geo.size, insets: raw, bar: bar,
                    regularWidth: sizeClass == .regular, dynamicTypeSize: dynamicTypeSize, rows: paletteRows,
                    foldPlace: foldPlace, rightToLeft: rightToLeft)
                ArtworkThumbnail(artwork: artwork, contentMode: .fit)
                    .frame(width: frame.width, height: frame.height)
                    .overlay {
                        if autosaver == nil { ProgressView().controlSize(.large) }
                    }
                    .position(x: frame.midX, y: frame.midY)
                    .onChange(of: raw, initial: true) { _, insets in
                        if !barMeasured {
                            barMeasured = true
                            barAtOpen = Self.statusBarAtOpen(insets)
                        }
                        if StatusBarAtOpen.isGone(barAtOpen, insets: insets) { barWentAway() }
                    }
            }
            // The status bar goes once the zoom has landed (the gallery behind it would move up
            // under the card as it came), and the painting is built in the safe area that follows.
            .statusBarHidden(hasLanded && !leaving)
            // Left to right, so positions are UIKit's whatever the language (the page is mirrored
            // already) and the safe area's leading edge is its left.
            .environment(\.layoutDirection, .leftToRight)
        } else {
            // A record with no size or paints (saved before they were kept): as it always lay.
            ArtworkThumbnail(artwork: artwork, contentMode: .fit)
                .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                .padding(20)
                .overlay {
                    if autosaver == nil { ProgressView().controlSize(.large) }
                }
                .onAppear { barWentAway() }
        }
    }

    /// The status bar as the waiting page found it, and the safe area once the painting has hidden
    /// it (read in a left-to-right view: leading is left).
    nonisolated struct StatusBarAtOpen: Equatable, Sendable {
        /// The safe area with the bar showing, as first read.
        var with: EdgeInsets
        /// The same without it.
        var without: EdgeInsets

        /// The safe area the painting will have: `without` while the insets are still `with`
        /// (UIKit says the bar is hidden a moment before the safe area follows, so whether it is
        /// hidden is never read), and the insets as they are once they have changed.
        static func predicted(_ bar: StatusBarAtOpen?, insets: EdgeInsets) -> EdgeInsets {
            guard let bar, insets == bar.with else { return insets }
            return bar.without
        }

        /// The safe area has followed the bar (or there was no bar in the way).
        static func isGone(_ bar: StatusBarAtOpen?, insets: EdgeInsets) -> Bool {
            guard let bar else { return true }
            return insets != bar.with
        }

        /// What hiding a bar of `barFrame` (UIKit's, in a screen `screenWidth` wide) takes from
        /// `insets`: across the top, the top where the bar alone keeps it clear (an iPad, a phone
        /// with no sensor housing); down a side (an iPhone Duo's), that side. Nil when the bar is
        /// hidden already, the window isn't the whole screen (Stage Manager, Split View: it keeps
        /// its bar) or nothing would change.
        static func measured(
            _ insets: EdgeInsets, barFrame: CGRect, barHidden: Bool, fullScreen: Bool, idiom: UIUserInterfaceIdiom,
            screenWidth: CGFloat
        ) -> StatusBarAtOpen? {
            guard !barHidden, fullScreen, barFrame.width > 0, barFrame.height > 0 else { return nil }
            var without = insets
            if barFrame.height > barFrame.width {
                if barFrame.midX > screenWidth / 2 {
                    without.trailing = max(0, insets.trailing - barFrame.width)
                } else {
                    without.leading = max(0, insets.leading - barFrame.width)
                }
            } else if idiom == .pad || insets.bottom == 0 {
                without.top = max(0, insets.top - barFrame.height)
            }
            return without == insets ? nil : StatusBarAtOpen(with: insets, without: without)
        }
    }

    /// The bar of the app's scene (it has one) as it stands, for `insets` read now.
    private static func statusBarAtOpen(_ insets: EdgeInsets) -> StatusBarAtOpen? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let bar = scene.statusBarManager
        else { return nil }
        return StatusBarAtOpen.measured(
            insets, barFrame: bar.statusBarFrame, barHidden: bar.isStatusBarHidden, fullScreen: scene.isFullScreen,
            idiom: scene.traitCollection.userInterfaceIdiom, screenWidth: scene.effectiveGeometry.coordinateSpace.bounds.width)
    }

    /// Where the waiting thumbnail lies in its reader (a view inside the safe area `insets`, read
    /// left to right, `readerSize` big): the page as the canvas will open it, in the safe area the
    /// painting will have (`StatusBarAtOpen.predicted`), moved into the reader's coordinates.
    static func waitingFrame(
        of opening: PaintingLayout.Opening, readerSize: CGSize, insets: EdgeInsets, bar: StatusBarAtOpen?,
        regularWidth: Bool, dynamicTypeSize: DynamicTypeSize, rows: PaletteRows, foldPlace: FoldPlace?,
        rightToLeft: Bool
    ) -> CGRect {
        let predicted = StatusBarAtOpen.predicted(bar, insets: insets)
        let screen = CGSize(
            width: readerSize.width + insets.leading + insets.trailing,
            height: readerSize.height + insets.top + insets.bottom)
        let size = CGSize(
            width: screen.width - predicted.leading - predicted.trailing,
            height: screen.height - predicted.top - predicted.bottom)
        let page = waitingPlace(
            of: opening, size: size, safe: directed(predicted, rightToLeft: rightToLeft), regularWidth: regularWidth,
            dynamicTypeSize: dynamicTypeSize, rows: rows, foldPlace: foldPlace, rightToLeft: rightToLeft)
        // `page` is in the whole screen's coordinates, UIKit's left and right.
        return page.offsetBy(dx: -insets.leading, dy: -insets.top)
    }

    private var rightToLeft: Bool { layoutDirection == .rightToLeft }

    /// The size, colors and state the page is laid out by: the loaded template's once there is one,
    /// the artwork's record until then.
    private func waitingTemplate(_ artwork: Artwork) -> PaintingLayout.Opening? {
        if let session = autosaver?.session {
            return PaintingLayout.Opening(
                size: CGSize(width: session.template.width, height: session.template.height),
                colors: PaletteBar.visibleColorCount(session.template), isComplete: session.isComplete,
                doors: finishedDoors(artwork))
        }
        guard artwork.width > 0, artwork.height > 0, artwork.colorCount > 0 else { return nil }
        return PaintingLayout.Opening(
            size: CGSize(width: artwork.width, height: artwork.height), colors: artwork.colorCount,
            isComplete: artwork.isComplete, doors: finishedDoors(artwork))
    }

    /// The doors after Finished the painting screen will show, as it counts them (its library
    /// picture is the artwork's), so the thumbnail waits where the finished painting opens.
    private func finishedDoors(_ artwork: Artwork) -> PaintingLayout.Doors? {
        PaintingLayout.Doors(
            count: FinishedDoor.shown(original: OriginalWork.of(artwork.sampleName) != nil).count,
            compactHeight: verticalSizeClass == .compact)
    }

    /// Safe-area insets read in a left-to-right view as they are in the painting's direction.
    static func directed(_ insets: EdgeInsets, rightToLeft: Bool) -> EdgeInsets {
        guard rightToLeft else { return insets }
        return EdgeInsets(top: insets.top, leading: insets.trailing, bottom: insets.bottom, trailing: insets.leading)
    }

    /// Where the canvas will first show the page of `opening` in a view of `size` inside `safe`:
    /// the whole screen's coordinates, as `PaintView` lays itself out there.
    static func waitingPlace(
        of opening: PaintingLayout.Opening, size: CGSize, safe: EdgeInsets, regularWidth: Bool,
        dynamicTypeSize: DynamicTypeSize, rows: PaletteRows, foldPlace: FoldPlace?, rightToLeft: Bool
    ) -> CGRect {
        let inputs = PaintingLayout.screen(
            size: size, safe: safe, regularWidth: regularWidth, dynamicTypeSize: dynamicTypeSize, rows: rows,
            colors: opening.colors, isComplete: opening.isComplete, doors: opening.doors, foldPlace: foldPlace,
            rightToLeft: rightToLeft)
        return PaintingLayout(inputs).page(of: opening.size, inputs: inputs, rightToLeft: rightToLeft)
    }

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
            if let autosaver, isBuilt {
                PaintView(
                    session: autosaver.session, title: artwork?.title ?? "", onClose: close,
                    onName: { startNaming() }, isNamed: artwork?.isNamed ?? true, asksForRating: true,
                    onTemplateFrame: canvasReport, onFirstFrame: heldScreen == nil ? nil : { releaseHeldScreen() },
                    onChange: changeAction, libraryPicture: artwork?.sampleName, startsBlank: startsBlank, hidesStatusBar: !leaving,
                    hidesLines: artwork?.paintsWithoutLines ?? false, onHidesLines: { linesHidden($0) })
                    .environment(\.sourcePhotoLoader, sourcePhotoLoader)
                    .environment(\.feedbackSource, feedbackSource)
                    .background { RevisionObserver(session: autosaver.session, onChange: autosaver.sessionChanged) }
                    // A new template (a re-cut) is a new session: the screen starts afresh on it.
                    .id(ObjectIdentifier(autosaver.session))
                    .environment(\.paintTogether, artwork.map { artwork in PaintTogetherAction(painting: artwork.id) { startTogether(artwork) } })
                    .task(id: ObjectIdentifier(autosaver.session)) {
                        TogetherLink.shared.paintingOpened(artworkID, session: autosaver.session)
                    }
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
                waitingPage(artwork)
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
        .animation(.settle, value: notice)
        .animation(.settle, value: showsLengthChip)
        .animation(.settle, value: recutFailed)
        .animation(.settle, value: saveFailed)
        .onChange(of: saveFailed) { _, failed in
            if failed { Announcer.announce(String(localized: "Couldn’t save progress")) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $change, onDismiss: changeEnded) { change in
            PaintingChangeView(model: change.model) { refinements in
                // What Done is compared with: the refinements as the tools opened, after the
                // load's own pin or rebase, not as read from disk (the fresh reader's review).
                presentedChange?.opened = refinements
            } onEdit: { refinements in
                Breadcrumbs.trace("change edit \(artworkID.uuidString), edits: \(refinements.edits.count)")
                keepChange(refinements, after: Self.changeKeepDelay)
            }
        }
        .modifier(RefineUnlockOffer(isPresented: $offersChangeUnlock) { openChange() })
        .sheet(isPresented: $fineTuning) {
            if let artwork {
                FineTuneSheet(
                    settings: artwork.settings,
                    // A painting saved before its paints were counted has none recorded.
                    paints: artwork.colorCount > 0 ? artwork.colorCount : artwork.settings.colorCount
                ) { recut(with: $0) }
                    .besideTheFold()
            }
        }
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
        .onChange(of: isUnderCover, initial: true) { _, under in
            if under { builtUnderCover = true }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else {
                absorbWidgetAreas()
                return
            }
            // ✎ Change's edits on disk before the hold below waits for the writes.
            if let refinements = presentedChange?.model.refinements, presentedChange?.opened != nil {
                keepChange(refinements, after: nil)
            }
            FeedbackEngine.shared.rest()
            autosaver?.saveNow(refreshThumbnail: true)
            if phase == .background {
                let library = library
                BackgroundSaving.shared.hold { await library.flush() }
                OutsideDesk.layOutOnLeaving(library)
            }
        }
        .onChange(of: precutTurn, initial: true) { _, turn in precutTurned(turn) }
        .onDisappear {
            TogetherLink.shared.paintingClosed(artworkID)
            regeneration?.cancel()
            recutting?.cancel()
            precuts.forget()
            releaseHeldScreen()
            autosaver?.saveNow(refreshThumbnail: true)
        }
    }

    /// More › Paint Together: shares the painting as a `.moonlight` file would be sent (its
    /// template and title, never its photo), and the painting screen paints together as soon as the
    /// session is up (`TogetherLink.bind`).
    private func startTogether(_ artwork: Artwork) {
        autosaver?.saveNow()
        let store = library.store, link = TogetherLink.shared
        Task {
            guard let data = try? await Background.run({
                try ArtworkExporter.sharedPainting(store: store, artwork: artwork, includesPhoto: false)
            }) else { return }
            await link.start(artwork: artwork.id, title: artwork.title, data: data)
        }
    }

    /// The areas the widget's Paint One Area showed painted while the app was away go into the
    /// painting on screen, are saved, and the shelf is laid out from there (`OutsideDesk`).
    private func absorbWidgetAreas() {
        // Not under ✎ Change's tools or during a replay: the taps wait for the next coming back.
        guard let autosaver, change == nil, presentedChange == nil, !autosaver.session.isReplaying else { return }
        let library = library
        Task {
            guard await OutsideDesk.absorb(into: autosaver.session, artwork: autosaver.artworkID) > 0 else { return }
            autosaver.saveNow(refreshThumbnail: true)
            await OutsideDesk.layOut(library)
        }
    }

    private func open() async {
        guard autosaver == nil, failure == nil else { return }
        #if DEBUG
        TourLog.trace("mark", "open begin")
        #endif
        // Before the painting is read: what the widget painted while the app was away.
        await OutsideDesk.comeBack(to: library, open: nil, only: artworkID)
        do {
            let document = try await library.loadForPainting(artworkID)
            _ = await RenderContext.ready()
            await present(document)
            #if DEBUG
            TourLog.trace("mark", "open end")
            #endif
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
            startsBlank = document.startsBlank
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
        // Should the safe area never be seen to follow (a window laid out otherwise), the painting
        // comes all the same.
        Task {
            try? await Task.sleep(for: Self.statusBarWait)
            barWentAway()
        }
        #if DEBUG
        markDemoReady()
        #endif
    }

    /// The most the painting waits, once landed, for the safe area to follow the status bar.
    private static let statusBarWait: Duration = .milliseconds(400)

    /// The status bar is out of the way: the painting may be built (`isBuilt`).
    private func barWentAway() {
        guard !statusBarGone else { return }
        withAnimation(isUnderCover ? nil : .easeOut(duration: 0.25)) { statusBarGone = true }
        #if DEBUG
        markDemoReady()
        #endif
    }

    #if DEBUG
    /// `gallery-open` and `gallery-received` are ready once the painting is on screen,
    /// `gallery-fine-tune` once Fine-Tune's sheet has risen over it.
    private func markDemoReady() {
        guard autosaver != nil, hasLanded, statusBarGone else { return }
        if ShellDemo.current == .galleryFineTune, !fineTuning {
            fineTuning = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                DemoMode.markReady()
            }
            return
        }
        guard ShellDemo.current == .galleryOpen || ShellDemo.current == .galleryOpenNew
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

    /// ✎ Change in the painting's bar, for a painting with a photo to draw over (a library picture's file will do).
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
                // Edits a ✎ Change left unsaved (iOS ended the app) come back where they were.
                model.load(artwork: artwork, photo: inputs.photo, template: template, refinements: inputs.unsaved ?? inputs.refinements)
                model.opensOnUnsavedEdits = inputs.unsaved != nil
                Breadcrumbs.trace("change opened \(id.uuidString), unsaved edits back: \(inputs.unsaved?.edits.count ?? 0)")
                let opened = PaintingChange(model: model, restored: inputs.unsaved != nil)
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
        changeKeeping?.cancel()
        changeKeeping = nil
        let model = ended.model
        // Closed before the tools opened (Cancel while Preparing) is a cancel too. Edits brought
        // back from an earlier ✎ Change are a change, though the tools opened on them.
        guard let opened = ended.opened, !model.refiningCancelled, ended.restored || model.refinements != opened else {
            model.cancelAll()
            // Nothing left unsaved: Cancel lets go of edits brought back too, and so does a load of
            // them that failed (else every ✎ Change would fail on them), into the painting's vault
            // (`ArtworkStore.Vault`), never deleted. Cancel while Preparing leaves them for the next time.
            var failed = false
            if case .failed = model.phase { failed = true }
            Breadcrumbs.trace("change closed \(artworkID.uuidString) without keeping, failed to open: \(failed)")
            if ended.opened != nil || model.refiningCancelled || failed { library.keepChange(nil, for: artworkID) }
            return
        }
        // On disk until the painting takes them (`adopt` removes them), so a Done that fails, or
        // iOS ending the app meanwhile, loses none.
        library.keepChange(model.refinements, for: artworkID)
        Breadcrumbs.trace("change done tapped \(artworkID.uuidString), \(model.refinements.edits.count) edits")
        changing = Task {
            defer { changing = nil }
            do {
                let draft = try await model.makeDraft()
                let document = try await library.adopt(draft, into: artworkID)
                Breadcrumbs.trace("change done \(artworkID.uuidString), \(draft.refinements.edits.count) edits")
                // The cuts kept were of the painting before the change.
                cuts = [:]
                precuts.forget()
                _ = await RenderContext.ready()
                await present(document, replacing: true)
            } catch is CancellationError {
            } catch {
                Log.library.error("Keeping ✎ Change on \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                Breadcrumbs.trace("change done failed \(artworkID.uuidString): \(error)")
                showChangeFailed()
            }
            model.cancelAll()
        }
    }

    /// How long ✎ Change's edits wait, the painter still drawing, before they are written.
    private static let changeKeepDelay: Duration = .seconds(1)

    /// Keeps the open ✎ Change's edits on disk (`Library.keepChange`) after `delay` without
    /// another edit, or at once (nil: the app is leaving the foreground); none when they are back
    /// where the tools opened.
    private func keepChange(_ refinements: TemplateRefinements, after delay: Duration?) {
        changeKeeping?.cancel()
        changeKeeping = nil
        guard let open = presentedChange, let opened = open.opened else { return }
        let kept = open.restored || refinements != opened ? refinements : nil
        let library = library, id = artworkID
        guard let delay else {
            library.keepChange(kept, for: id)
            return
        }
        changeKeeping = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            library.keepChange(kept, for: id)
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
            progress: recutting == nil ? nil : recutProgress,
            cutAreas: cuts.mapValues { $0.template.regions.count },
            isCustom: isCustomCut,
            onPick: recut(to:),
            onFineTune: fineTune)
    }

    /// The re-cut's progress, 0…1: of a cut made ahead the painter is waiting for, else of the
    /// cut being made and saved.
    private var recutProgress: Double {
        if let waiting = precuts.awaitedProgress { return waiting }
        return library.regenerating[artworkID] ?? 0
    }

    /// When the other lengths are cut ahead: the chip showing on a painting settled on screen,
    /// with no re-cut, ✎ Change or recovery under way, and the app in front. A new cut on
    /// screen (a new session) starts them again, after `LengthPrecuts.settle`.
    private struct PrecutTurn: Equatable {
        let session: ObjectIdentifier
        let length: String?
        let isCustom: Bool
    }

    private var precutTurn: PrecutTurn? {
        guard showsLengthChip, recutting == nil, changing == nil, change == nil, regeneration == nil,
              scenePhase == .active, let autosaver, let artwork else { return nil }
        return PrecutTurn(session: ObjectIdentifier(autosaver.session), length: artwork.paintingLength, isCustom: isCustomCut)
    }

    private func precutTurned(_ turn: PrecutTurn?) {
        guard let turn, let artwork else {
            precuts.stop()
            // Begun: no length will be picked, so nothing found is kept.
            if autosaver?.session.isStarted == true { precuts.forget() }
            return
        }
        precuts.resume(
            artwork: artwork, current: turn.length.flatMap(PaintingLength.init(rawValue:)), includingCurrent: turn.isCustom,
            skipping: Set(cuts.keys), library: library
        ) { cut in
            cuts[cut.length] = Cut(template: cut.template, settings: cut.settings)
        }
    }

    /// The painting was cut with the painter's own settings, by Fine-Tune or the create flow's
    /// sliders: no length's suggestion, so the cuts keep none of it. SideStore and Debug builds,
    /// with Fine-Tune: the release's chip is as it was.
    private var isCustomCut: Bool {
        return artwork?.settingsOrigin == SettingsOrigin.custom.rawValue
    }

    /// Fine-Tune's sheet, in SideStore and Debug builds.
    private var fineTune: (() -> Void)? {
        return { fineTuning = true }
    }

    /// Cuts the painting again with the painter's own `settings`, from Fine-Tune
    /// (`Library.retune`), and opens it in place. The lengths' cuts kept are forgotten: picking
    /// one again cuts it afresh, as the length chip promised before the painter tuned it.
    private func recut(with settings: GenerationSettings) {
        guard recutting == nil, changing == nil, regeneration == nil, let autosaver,
              settings != artwork?.settings.normalized else { return }
        autosaver.saveNow()
        recutFailed = false
        recutting = Task {
            do {
                let document = try await library.retune(artwork: artworkID, settings: settings)
                cuts = [:]
                precuts.forget()
                _ = await RenderContext.ready()
                await present(document, replacing: true)
                Announcer.announce(LengthChip.summary(regionCount: document.template.regions.count))
            } catch is CancellationError {
            } catch {
                showRecutFailure(error)
            }
            recutting = nil
        }
    }

    /// How long the length chip's menu takes to close after a pick. A cut made ahead is in the
    /// painting a few milliseconds after the pick, and the new screen built then (with the old
    /// one's picture taken to hold over it, `holdOldScreen`) caught the menu halfway closed: its
    /// glass froze in that picture as a blank blob over a canvas that stuttered (the nightly of
    /// November 24, painting-company row 361). So a cut made already waits for the menu to be
    /// gone before it is saved and opened (saving it redraws the gallery and the chip too).
    static let lengthMenuCloses = Duration.milliseconds(450)

    /// Cuts the painting again at `length` (`Library.recut`) and opens the new cut in place.
    private func recut(to length: PaintingLength) {
        guard recutting == nil, changing == nil, regeneration == nil, let autosaver,
              isCustomCut || length.rawValue != artwork?.paintingLength else { return }
        let picked = ContinuousClock.now
        autosaver.saveNow()
        recutFailed = false
        // A cut of the painter's own settings is no length's: a length picked is cut afresh.
        if !isCustomCut, let artwork, let current = artwork.paintingLength.flatMap(PaintingLength.init(rawValue:)),
           cuts[current] == nil {
            cuts[current] = Cut(template: autosaver.session.template, settings: artwork.settings)
        }
        let kept = cuts[length]
        // A length not cut ahead yet: the cut under way is waited for, else one starts now on
        // the photo's analysis found already. Claimed at once, before anything stops the others.
        let precut = kept == nil ? artwork.map { precuts.claim(length, of: $0, library: library) } : nil
        recutting = Task {
            do {
                let document: PaintingDocument
                if let kept {
                    try await Task.sleep(until: picked + Self.lengthMenuCloses, clock: .continuous)
                    document = try await library.restoreCut(
                        artwork: artworkID, length: length, template: kept.template, settings: kept.settings)
                } else {
                    if let precut {
                        let made = try await withTaskCancellationHandler {
                            try await precut.value
                        } onCancel: {
                            precut.cancel()
                        }
                        try await Task.sleep(until: picked + Self.lengthMenuCloses, clock: .continuous)
                        document = try await library.restoreCut(
                            artwork: artworkID, length: length, template: made.template, settings: made.settings)
                    } else {
                        document = try await library.recut(artwork: artworkID, length: length)
                    }
                }
                if let made = library.artwork(with: artworkID)?.settings {
                    cuts[length] = Cut(template: document.template, settings: made)
                }
                _ = await RenderContext.ready()
                await present(document, replacing: true)
                Announcer.announce(LengthChip.summary(regionCount: document.template.regions.count))
            } catch is CancellationError {
            } catch {
                showRecutFailure(error)
            }
            precuts.finished()
            recutting = nil
        }
    }

    private func showRecutFailure(_ error: any Error) {
        Log.library.error("Re-cutting \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        recutFailedText = String(localized: "Couldn’t cut the picture again")
        recutFailed = true
        Announcer.announce(recutFailedText)
        Task {
            try? await Task.sleep(for: .seconds(4))
            recutFailed = false
        }
    }

    private func delete() {
        library.delete(artworkID)
        onClose()
    }

    private func close() {
        autosaver?.saveNow(refreshThumbnail: true)
        // The status bar first, the pop on the next turn: popped while the painting still hid it,
        // the gallery's large title and its count came back about 120 points low, over the first
        // card, for the second the zoom takes, then jumped into place (painting-company row 324).
        // The edge swipe back doesn't do this.
        leaving = true
        Task { onClose() }
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
    /// It opened on edits an earlier ✎ Change left unsaved (`Library.changeInputs`).
    var restored = false
    var opened: TemplateRefinements?
}
