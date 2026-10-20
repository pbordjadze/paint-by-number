import CoreGraphics
import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

/// The create flow's draft: what is kept (`CreateDraft`, `DraftStore`), when it is written and
/// removed (`Drafts`), that a damaged one is no draft, and that a flow resumes from one.
@MainActor
struct DraftTests {
    let root = Fixtures.temporaryDirectory()

    private var store: DraftStore { DraftStore(root: root.appending(path: "Drafts", directoryHint: .isDirectory)) }

    private func photo(_ size: Int = 300) throws -> CGImage {
        try #require(TemplateRasterizer.image(Fixtures.stripes(), style: .painting, maxPixelSize: size))
    }

    private func refinements() -> TemplateRefinements {
        var refinements = TemplateRefinements()
        refinements.lines = [
            .init(kind: .draw, radius: 0, points: [SIMD2(0.2, 0.4), SIMD2(0.7, 0.45)]),
            .init(kind: .erase, radius: 0.02, points: [SIMD2(0.5, 0.5)]),
        ]
        refinements.edits = [
            .draw(points: [SIMD2(220, 290), SIMD2(480, 262), SIMD2(770, 330)], closed: false),
            .erase(path: [SIMD2(500, 400)], radius: 12),
            .fill(at: SIMD2(300, 150), color: SIMD3(0.6, 0.05, 0.05)),
        ]
        refinements.strokes = [TemplateRefinements.Stroke(kind: .more, radius: 0.1, points: [SIMD2(0.3, 0.3)])]
        refinements.addedText = [TemplateRefinements.textLine(from: SIMD2(0.1, 0.1), to: SIMD2(0.4, 0.2))]
        return refinements
    }

    private func draft(_ photoID: UUID = UUID(), title: String = "Stripes") -> CreateDraft {
        CreateDraft(
            photoID: photoID, title: title, defaultTitle: "March 3",
            settings: GenerationSettings(colorCount: 12, detail: 0.25, smoothness: 0.75), lines: 0.8,
            sampleName: "great-wave", refinements: refinements())
    }

    private func exists(_ file: DraftStore.File) -> Bool {
        FileManager.default.fileExists(atPath: store.url(file).path)
    }

    private func photoWidth() -> Int? { ImageCodec.image(at: store.url(.source))?.width }

    // MARK: The store

    @Test func roundTripsItsSettingsRefinementsAndPhoto() throws {
        let store = store
        let saved = draft()
        #expect(try store.read() == nil)
        try store.write(saved, photo: try photo())
        for file in DraftStore.File.allCases { #expect(exists(file), "\(file.rawValue)") }
        #expect(try store.read() == saved)
        #expect(try store.read()?.refinements.edits == refinements().edits, "The draft's edits weren't kept in its refinements.json")
        #expect(photoWidth() == 300)
        #expect(try !store.photoData().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Drafts/.staging").path).isEmpty)
    }

    @Test func rewritingKeepsTheStoredPhoto() throws {
        let store = store
        let saved = draft()
        try store.write(saved, photo: try photo())
        let first = try Data(contentsOf: store.url(.source))

        var changed = saved
        changed.title = "Renamed"
        changed.refinements.lines.removeLast()
        try store.write(changed, photo: nil)
        #expect(try store.read() == changed)
        #expect(try Data(contentsOf: store.url(.source)) == first)

        let empty = DraftStore(root: root.appending(path: "Empty", directoryHint: .isDirectory))
        #expect(throws: DraftStore.StoreError.missingPhoto) { try empty.write(saved, photo: nil) }
        #expect(try empty.read() == nil)
    }

    // MARK: Keeping it

    @Test func writesAtOnceOnDemandAndSurvivesALaunch() async throws {
        let drafts = Drafts(store: store)
        let saved = draft()
        drafts.keep(saved, photo: try photo())
        #expect(drafts.current == nil, "The draft was written before its delay")
        drafts.saveNow()
        await drafts.flush()
        #expect(drafts.current == saved)

        let relaunched = Drafts(store: store)
        #expect(relaunched.current == saved)
        let opened = try #require(await relaunched.open())
        #expect(opened.draft == saved)
        #expect(!opened.photo.isEmpty)
    }

    @Test func writesTheLatestChangeAndEncodesThePhotoOnce() async throws {
        let drafts = Drafts(store: store)
        let id = UUID()
        drafts.keep(draft(id, title: "One"), photo: try photo(300))
        drafts.keep(draft(id, title: "Two"), photo: try photo(300))
        await drafts.flush()
        #expect(drafts.current?.title == "Two")
        #expect(try store.read()?.title == "Two")
        #expect(photoWidth() == 300)

        // Another change to the same photo keeps the file: the photo handed in now is not used.
        drafts.keep(draft(id, title: "Three"), photo: try photo(200))
        await drafts.flush()
        #expect(try store.read()?.title == "Three")
        #expect(photoWidth() == 300)
    }

    @Test func anotherPhotoReplacesTheDraft() async throws {
        let drafts = Drafts(store: store)
        drafts.keep(draft(), photo: try photo(300))
        await drafts.flush()
        let replacement = draft(title: "Second")
        drafts.keep(replacement, photo: try photo(200))
        await drafts.flush()
        #expect(drafts.current == replacement)
        #expect(try store.read() == replacement)
        #expect(photoWidth() == 200)
    }

    // MARK: Removing it

    @Test func droppingRemovesOnlyItsOwnPhotosDraft() async throws {
        let drafts = Drafts(store: store)
        let saved = draft()
        drafts.keep(saved, photo: try photo())
        await drafts.flush()

        drafts.drop(photoID: UUID())
        await drafts.flush()
        #expect(drafts.current == saved && exists(.draft), "Another photo's flow removed the draft")

        drafts.drop(photoID: saved.photoID)
        await drafts.flush()
        #expect(drafts.current == nil)
        for file in DraftStore.File.allCases { #expect(!exists(file), "\(file.rawValue)") }
        #expect(Drafts(store: store).current == nil)
    }

    @Test func droppingCancelsAWriteStillWaiting() async throws {
        let drafts = Drafts(store: store)
        let kept = draft()
        drafts.keep(kept, photo: try photo())
        await drafts.flush()

        // A new photo's draft undone before it landed leaves the earlier draft alone.
        let newer = draft()
        drafts.keep(newer, photo: try photo(200))
        drafts.drop(photoID: newer.photoID)
        await drafts.flush()
        #expect(drafts.current == kept)
        #expect(try store.read() == kept)
        #expect(photoWidth() == 300)
    }

    @Test func discardRemovesTheDraft() async throws {
        let drafts = Drafts(store: store)
        drafts.keep(draft(), photo: try photo())
        await drafts.flush()
        #expect(drafts.current != nil)

        drafts.discard()
        await drafts.flush()
        #expect(drafts.current == nil)
        #expect(try store.read() == nil)
        #expect(await drafts.open() == nil)
    }

    @Test func aWriteWaitingWhenTheDraftIsDiscardedNeverLands() async throws {
        let drafts = Drafts(store: store)
        drafts.keep(draft(), photo: try photo())
        drafts.discard()
        await drafts.flush()
        #expect(drafts.current == nil)
        #expect(try store.read() == nil)
    }

    // MARK: Damage

    @Test(arguments: DraftStore.File.allCases)
    func aDamagedDraftIsNoDraftAndIsRemoved(file: DraftStore.File) throws {
        let store = store
        try store.write(draft(), photo: try photo())
        switch file {
        case .draft, .refinements: try Data("not json".utf8).write(to: store.url(file))
        case .source: try FileManager.default.removeItem(at: store.url(file))
        }
        let folder = store.url(.draft).deletingLastPathComponent()

        let drafts = Drafts(store: store)
        #expect(drafts.current == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path), "The damaged draft was kept")
    }

    /// A draft that can't be read just now (here: no permission, as a data protection error would
    /// leave it) is no damage: it is kept, and the next launch that can read it has it.
    @Test func aDraftThatCantBeReadNowIsKept() throws {
        let store = store
        let saved = draft()
        try store.write(saved, photo: try photo())
        let fm = FileManager.default
        let json = store.url(.draft).path
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: json)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: json) }

        #expect(Drafts(store: store).current == nil)
        #expect(fm.fileExists(atPath: json), "A draft that couldn't be read just now was removed")

        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: json)
        #expect(Drafts(store: store).current == saved)
    }

    @Test func aDraftWhosePhotoCantBeReadNowIsKeptWhenOpening() async throws {
        let store = store
        let saved = draft()
        try store.write(saved, photo: try photo())
        let fm = FileManager.default
        let source = store.url(.source).path
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: source)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source) }

        let drafts = Drafts(store: store)
        #expect(await drafts.open() == nil)
        #expect(drafts.current == saved, "A draft that couldn't be opened just now was dropped")
        #expect(fm.fileExists(atPath: source), "A draft that couldn't be opened just now was removed")

        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source)
        #expect(await drafts.open()?.draft == saved)
    }

    @Test func aPhotoThatDoesNotDecodeIsFoundWhenOpening() async throws {
        let store = store
        try store.write(draft(), photo: try photo())
        try Data("not a jpeg".utf8).write(to: store.url(.source))

        let drafts = Drafts(store: store)
        #expect(drafts.current != nil, "Only opening looks into the photo")
        #expect(await drafts.open() == nil)
        #expect(drafts.current == nil)
        #expect(try store.read() == nil)
    }

    @Test func staleStagingIsClearedAtLaunch() throws {
        let stale = root.appending(path: "Drafts/.staging/Current", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        _ = Drafts(store: store)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    // MARK: In the library

    /// The drafts folder beside the artworks is not an artwork, and a draft outlives the library
    /// reloading.
    @Test func theLibraryKeepsItsDraftBesideTheArtworks() async throws {
        func library() -> Library { Library(store: ArtworkStore(root: root)) }
        let first = library()
        let saved = draft()
        first.drafts.keep(saved, photo: try photo())
        await first.drafts.flush()
        let artwork = try await first.create(
            ArtworkDraft(title: "Stripes", template: Fixtures.stripes(), settings: GenerationSettings(colorCount: 12)))

        let second = library()
        #expect(second.artworks.map(\.id) == [artwork.id])
        #expect(second.drafts.current == saved)
    }

    // MARK: The create flow

    /// A flow has a draft once its photo is refined, with what the painter set.
    @Test func aFlowHasADraftOnlyOnceItIsRefined() async throws {
        let model = CreateModel()
        #expect(model.draft == nil)
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        #expect(model.draft == nil, "A painting nobody refined has a draft")

        model.title = "Winter Fox"
        model.refine(refinements())
        let kept = try #require(model.draft)
        #expect(kept.title == "Winter Fox" && kept.defaultTitle == model.defaultTitle)
        #expect(kept.photoID == model.photoID && kept.sampleName == "red-fox")
        #expect(kept.settings == model.settings && kept.lines == model.lines)
        #expect(kept.refinements == refinements())

        model.refine(TemplateRefinements())
        #expect(model.draft == nil, "Refinements undone to nothing left a draft")
        model.load(sample: try #require(Sample.named("milkmaid")))
        #expect(model.photoID != kept.photoID)
        model.cancelAll()
    }

    /// Resuming a draft puts back its photo, title, settings (not the suggestion's) and
    /// refinements, and generates them.
    @Test func aFlowResumesWhereTheDraftLeftOff() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let suggested = model.settings
        model.detail = suggested.detail < 0.75 ? Double(suggested.detail) + 0.25 : Double(suggested.detail) - 0.25
        model.settingsChanged()
        model.title = "Winter Fox"
        model.refine(refinements())
        try await waitUntil { model.isFinal }
        let saved = try #require(model.draft)
        let source = try #require(model.source)
        let jpeg = try #require(ImageCodec.jpegData(source.preview, quality: 0.88))

        let resumed = CreateModel()
        resumed.load(draft: saved, photo: jpeg)
        #expect(resumed.draft == nil, "The draft was offered before its settings were put back")
        try await waitUntil { resumed.isFinal }
        #expect(resumed.draft == saved)
        #expect(resumed.photoID == saved.photoID && resumed.source?.sampleName == "red-fox")
        #expect(resumed.refinements == saved.refinements && resumed.settings == saved.settings)
        #expect(resumed.preview?.refinements == saved.refinements && resumed.preview?.settings == saved.settings)
        #expect(resumed.decision != nil && resumed.settingsOrigin == .custom)

        let made = try await resumed.makeDraft()
        #expect(made.title == "Winter Fox" && made.refinements == saved.refinements && made.settings == saved.settings)
        #expect(made.sampleName == "red-fox")
    }

    /// A blank start is a refinement of its own: the flow keeps a draft of it before any edit, and
    /// the draft resumes blank, the photo as one area.
    @Test func aBlankStartIsKeptAndResumesBlank() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        model.start(from: .blank)
        try await waitUntil { model.refinements.start == .blank && model.isFinal }
        let saved = try #require(model.draft, "A blank start left no draft")
        #expect(saved.refinements.start == .blank && saved.refinements.edits.isEmpty)

        let store = store
        try store.write(saved, photo: try #require(model.source?.preview))
        let stored = try store.read()
        let read = try #require(stored)
        #expect(read == saved)

        let resumed = CreateModel()
        resumed.load(draft: read, photo: try store.photoData())
        try await waitUntil { resumed.isFinal }
        #expect(resumed.refineStart == .blank && resumed.draft == read)
        #expect(resumed.preview?.template.regions.count == 1)
        model.cancelAll()
        resumed.cancelAll()
    }

    /// The edits a draft keeps are laid again on resuming it, in order, as the editor lays them:
    /// the template shown is the editor's result on the template the generator makes, which
    /// clearing the edits shows.
    @Test func resumingADraftLaysItsEditsAgain() async throws {
        let model = CreateModel()
        model.load(sample: try #require(Sample.named("red-fox")))
        try await waitUntil { model.isFinal }
        let template = try #require(model.preview?.template)
        let w = Float(template.width), h = Float(template.height)
        let drawn = TemplateEditor.Edit.draw(points: [SIMD2(0.42 * w, 0.5 * h), SIMD2(0.5 * w, 0.46 * h), SIMD2(0.58 * w, 0.5 * h)])
        let serial = model.edit(drawn)
        try await waitUntil { model.settledEdits >= serial && model.isFinal }
        let edit = TemplateEditor.painted(drawn, on: template, photo: try #require(model.source?.image))
        let saved = try #require(model.draft)
        #expect(saved.refinements.edits == [edit])

        let store = store
        let photo = try #require(model.source?.preview)
        try store.write(saved, photo: photo)
        let stored = try store.read()
        let read = try #require(stored)
        #expect(read == saved && read.refinements.edits == [edit])

        let resumed = CreateModel()
        resumed.load(draft: read, photo: try store.photoData())
        try await waitUntil { resumed.isFinal }
        #expect(resumed.refinements.edits == [edit] && resumed.draft == read)
        let laid = try #require(resumed.preview?.template)
        resumed.refine(TemplateRefinements())
        try await waitUntil { resumed.refinements.isEmpty && resumed.isFinal }
        let base = try #require(resumed.preview?.template)
        #expect(laid != base)
        #expect(try TemplateEditor.apply(edit, to: base).template == laid)
        model.cancelAll()
        resumed.cancelAll()
    }
}
