import Foundation
import PaintCore
import Testing
@testable import PaintByNumber

@MainActor
struct PaintingAutosaverTests {
    let root = Fixtures.temporaryDirectory()
    let faults = WriteFaults()

    private func makeLibrary() -> Library { Library(store: ArtworkStore(root: root, writeFaults: faults)) }

    /// A library holding one painting of `count` stripes, and a session on it.
    private func open(
        count: Int, delay: Duration = .seconds(5), maxWait: Duration = .seconds(10)
    ) async throws -> (library: Library, artwork: Artwork, autosaver: PaintingAutosaver) {
        let library = makeLibrary()
        let template = Fixtures.stripes(count: count)
        let artwork = try await library.create(
            ArtworkDraft(title: "Stripes", template: template, settings: GenerationSettings(colorCount: 12), photo: nil, sampleName: nil))
        let autosaver = PaintingAutosaver(
            session: PaintingSession(template: template), artworkID: artwork.id, library: library, delay: delay, maxWait: maxWait)
        return (library, artwork, autosaver)
    }

    private func paint(_ region: Int, in autosaver: PaintingAutosaver) {
        autosaver.session.paint([region], from: .zero, animated: false)
        autosaver.sessionChanged()
    }

    /// Fills that never pause for the debounce still reach the disk, at the latest `maxWait`
    /// after the first of them.
    @Test func continuousPaintingSavesAfterTheMaximumWait() async throws {
        let (library, artwork, autosaver) = try await open(count: 12, delay: .seconds(5), maxWait: .milliseconds(250))
        for region in 0..<10 {
            paint(region, in: autosaver)
            try await Task.sleep(for: .milliseconds(40))
        }
        // No quiet moment has come (the debounce is 5 s), yet progress was handed over.
        let handedOver = try #require(library.artwork(with: artwork.id)).paintedCount
        #expect(handedOver > 0)
        await library.flush()
        #expect(try await makeLibrary().loadForPainting(artwork.id).progress.paintedCount == handedOver)

        autosaver.saveNow()
        #expect(library.artwork(with: artwork.id)?.paintedCount == 10)
    }

    /// A single change is saved once it has been quiet for the delay.
    @Test func aChangeIsSavedAfterTheDelay() async throws {
        let (library, artwork, autosaver) = try await open(count: 5, delay: .milliseconds(80))
        paint(0, in: autosaver)
        #expect(library.artwork(with: artwork.id)?.paintedCount == 0)
        try await Task.sleep(for: .milliseconds(500))
        #expect(library.artwork(with: artwork.id)?.paintedCount == 1)
    }

    /// Closing saves what the debounce still holds.
    @Test func closingSavesAtOnce() async throws {
        let (library, artwork, autosaver) = try await open(count: 5)
        paint(0, in: autosaver)
        paint(1, in: autosaver)
        autosaver.saveNow(refreshThumbnail: true)
        await autosaver.thumbnailTask?.value
        await library.flush()
        #expect(try await makeLibrary().loadForPainting(artwork.id).progress.paintedCount == 2)
        #expect(library.artwork(with: artwork.id)?.thumbnailVersion == artwork.thumbnailVersion + 1)
    }

    @Test func aFinishedPaintingIsSavedImmediately() async throws {
        let (library, artwork, autosaver) = try await open(count: 2)
        paint(0, in: autosaver)
        paint(1, in: autosaver)
        #expect(library.artwork(with: artwork.id)?.isComplete == true)
        await autosaver.thumbnailTask?.value
        #expect(library.artwork(with: artwork.id)?.thumbnailVersion == artwork.thumbnailVersion + 1)
    }

    /// A thumbnail that didn't reach the disk is made again on the next save, not skipped
    /// because its revision was already tried.
    @Test func aFailedThumbnailIsRetried() async throws {
        let (library, artwork, autosaver) = try await open(count: 5)
        paint(0, in: autosaver)
        faults.fail(.thumbnail)
        autosaver.saveNow(refreshThumbnail: true)
        await autosaver.thumbnailTask?.value
        #expect(library.artwork(with: artwork.id)?.thumbnailVersion == artwork.thumbnailVersion)

        faults.heal(.thumbnail)
        autosaver.saveNow(refreshThumbnail: true)
        await autosaver.thumbnailTask?.value
        #expect(library.artwork(with: artwork.id)?.thumbnailVersion == artwork.thumbnailVersion + 1)

        // Done for this revision: leaving again renders nothing.
        autosaver.saveNow(refreshThumbnail: true)
        await autosaver.thumbnailTask?.value
        #expect(library.artwork(with: artwork.id)?.thumbnailVersion == artwork.thumbnailVersion + 1)
    }
}
